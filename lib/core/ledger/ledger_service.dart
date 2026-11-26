import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/accounts_dao.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/mandate_tracker.dart';
import 'package:rivero/core/utils/amount_parser.dart';

/// The one place where a transaction's money effects are applied:
/// physical balance + expense-bucket spend. Every capture path (notification,
/// swipe-confirm, manual entry) must go through here so nothing is skipped or
/// applied twice.
///
/// Budget rules:
/// * cash-like outflows (expense, ATM, cash) consume the expense bucket;
/// * credit-card purchases do NOT (they are a liability that Safe-to-Spend
///   subtracts separately) — the budget is consumed when the bill is paid;
/// * refunds on a bank account give budget back.
class LedgerService {
  LedgerService(this.db);

  final RiveroDatabase db;

  static const Set<TransactionType> _autopayTypes = {
    TransactionType.expense,
    TransactionType.creditCardPurchase,
    TransactionType.cashExpenditure,
  };

  static const Set<TransactionType> _cashOutflows = {
    TransactionType.expense,
    TransactionType.atmWithdrawal,
    TransactionType.cashExpenditure,
  };

  /// Records a user-entered transaction as confirmed and applies its effects.
  /// [amountMinorUnits] is signed (negative = money out). Returns its id.
  Future<String> recordManual({
    required String accountId,
    required int amountMinorUnits,
    required TransactionType type,
    required String merchant,
    required String category,
    String? bucketId,
    String? note,
    DateTime? at,
    String? attachmentPath,
  }) async {
    final now = DateTime.now();
    final id = 'txn-manual-${now.microsecondsSinceEpoch}';
    return await db.transaction(() async {
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: Value(id),
          physicalAccountId: Value(accountId),
          allocationBucketId: Value(bucketId),
          amountMinorUnits: Value(amountMinorUnits),
          transactionType: Value(type),
          transactionState: const Value(TransactionState.confirmed),
          merchant: Value(merchant),
          category: Value(category),
          userNotes: Value(
            note == null || note.trim().isEmpty ? null : note.trim(),
          ),
          attachmentPath: Value(attachmentPath),
          transactionTimestamp: Value(at ?? now),
          createdAt: Value(now),
        ),
      );
      final saved = await db.transactionsDao.getTransactionById(id);
      if (saved != null) await applyEffects(saved);
      return id;
    });
  }

  /// Sets an account's balance to what the user says it is (outstanding for
  /// a card), recording the difference as a visible "Balance update" entry
  /// so history stays explainable. Returns the change applied (0 = none).
  Future<int> setBalance(String accountId, int newBalanceMinorUnits) =>
      db.transaction(() async {
        final acc = await db.accountsDao.getPhysicalAccountById(accountId);
        if (acc == null) return 0;
        final diff = newBalanceMinorUnits - acc.balanceMinorUnits;
        if (diff == 0) return 0;
        await recordManual(
          accountId: accountId,
          amountMinorUnits: diff,
          type: TransactionType.balanceAdjustment,
          merchant: 'Balance update',
          category: 'Adjustment',
        );
        // From now on this balance is the truth: older entries accepted or
        // deleted later are already inside it.
        await db.accountsDao.setKnownBalance(
          accountId,
          newBalanceMinorUnits,
          DateTime.now(),
        );
        return diff;
      });

  /// Rows that only record history (statement imports) never touched a
  /// balance, so deleting them must not reverse anything.
  static bool historyOnly(LedgerTransaction t) => t.id.startsWith('import-');

  /// Deletes a transaction, first undoing its balance and budget effects if
  /// they were applied. A linked transfer/refund partner is unlinked, and a
  /// split or loan made from it that nobody has paid back yet goes too.
  Future<void> remove(String transactionId) => db.transaction(() async {
    final t = await db.transactionsDao.getTransactionById(transactionId);
    if (t == null) return;
    final applied =
        !historyOnly(t) &&
        (t.transactionState == TransactionState.confirmed ||
            t.transactionState == TransactionState.reconciled);
    if (applied) {
      // Only if this entry is what moved the balance (see balanceAsOf).
      // Undo what it really changed: a balance that stopped at zero took
      // less than the full amount.
      if (await _movesBalance(t)) {
        await db.accountsDao.adjustAccountBalance(
          t.physicalAccountId,
          -(t.appliedMinorUnits ?? t.amountMinorUnits),
        );
      }
      final spend = await _budgetSpend(t);
      if (spend != 0) {
        final bucketId =
            t.allocationBucketId ?? await _defaultExpenseBucketId();
        if (bucketId != null) {
          await db.accountsDao.recordBucketSpend(bucketId, -spend);
        }
      }
      await _markCategoryPaid(t, sign: -1);
    } else if (historyOnly(t)) {
      // A plan payment recorded after the fact: the category is unpaid again.
      await _markCategoryPaid(t, sign: -1);
    }
    final partner = t.linkedTransactionId;
    if (partner != null) {
      await (db.update(
        db.transactions,
      )..where((x) => x.id.equals(partner))).write(
        const TransactionsCompanion(
          linkedTransactionId: Value(null),
          isInternalTransfer: Value(false),
        ),
      );
    }
    // The bill or loan no longer exists: its open, unpaid dues go with it.
    await (db.delete(db.dues)..where(
          (d) =>
              d.sourceTransactionId.equals(transactionId) &
              d.receivedMinorUnits.equals(0),
        ))
        .go();
    await db.transactionsDao.deleteTransaction(transactionId);
  });

  /// Points [transactionId] at another account: the payment really came from
  /// (or the money landed in) a different one. What it did to the old account
  /// and the budget is undone, then done again for the new one. Moving
  /// between a bank and a card turns spending into card spending and back.
  /// Transfer legs are left alone (they belong to a pair).
  Future<void> changeAccount(
    String transactionId,
    String accountId,
  ) => db.transaction(() async {
    final t = await db.transactionsDao.getTransactionById(transactionId);
    if (t == null || t.physicalAccountId == accountId) return;
    if (t.isInternalTransfer || t.linkedTransactionId != null) {
      throw StateError('A transfer cannot be moved to another account');
    }
    final to = await db.accountsDao.getPhysicalAccountById(accountId);
    if (to == null) return;
    final applied =
        !historyOnly(t) &&
        (t.transactionState == TransactionState.confirmed ||
            t.transactionState == TransactionState.reconciled);
    if (applied) {
      if (await _movesBalance(t)) {
        await db.accountsDao.adjustAccountBalance(
          t.physicalAccountId,
          -(t.appliedMinorUnits ?? t.amountMinorUnits),
        );
      }
      final spend = await _budgetSpend(t);
      final bucket = t.allocationBucketId ?? await _defaultExpenseBucketId();
      if (spend != 0 && bucket != null) {
        await db.accountsDao.recordBucketSpend(bucket, -spend);
      }
    }
    final from = await db.accountsDao.getPhysicalAccountById(
      t.physicalAccountId,
    );
    var type = t.transactionType;
    if (from != null && from.isLiability != to.isLiability) {
      if (to.isLiability && type == TransactionType.expense) {
        type = TransactionType.creditCardPurchase;
      } else if (!to.isLiability &&
          type == TransactionType.creditCardPurchase) {
        type = TransactionType.expense;
      }
    }
    await (db.update(
      db.transactions,
    )..where((x) => x.id.equals(transactionId))).write(
      TransactionsCompanion(
        physicalAccountId: Value(accountId),
        transactionType: Value(type),
      ),
    );
    if (!applied) return;
    final moved = (await db.transactionsDao.getTransactionById(transactionId))!;
    var now = 0;
    if (await _movesBalance(moved)) {
      final before = await _balance(accountId);
      await db.accountsDao.adjustAccountBalance(
        accountId,
        moved.amountMinorUnits,
      );
      now = await _balance(accountId) - before;
    }
    await (db.update(db.transactions)..where((x) => x.id.equals(transactionId)))
        .write(TransactionsCompanion(appliedMinorUnits: Value(now)));
    final spend = await _budgetSpend(moved);
    final bucket = moved.allocationBucketId ?? await _defaultExpenseBucketId();
    if (spend != 0 && bucket != null) {
      await db.accountsDao.recordBucketSpend(bucket, spend);
    }
  });

  /// Whether [t] can have its amount, date or name corrected: not one leg
  /// of a transfer or another pair (both legs must keep matching), and not a
  /// history-only import.
  static bool canEdit(LedgerTransaction t) =>
      !t.isInternalTransfer && t.linkedTransactionId == null && !historyOnly(t);

  /// Corrects what a payment was: its amount (a positive amount; the entry
  /// keeps its direction), when it happened, or who it was with. If it
  /// already counted, its old balance, budget and category effects are undone
  /// and the corrected ones applied, so balances move by the difference.
  /// Autopay roll-forward and ATM cash moves are not redone. Throws a
  /// [StateError] for entries [canEdit] refuses.
  Future<void> edit(
    String transactionId, {
    int? amountMinorUnits,
    DateTime? timestamp,
    String? merchant,
  }) => db.transaction(() async {
    final t = await db.transactionsDao.getTransactionById(transactionId);
    if (t == null) return;
    if (!canEdit(t)) {
      throw StateError('A transfer or imported entry cannot be edited');
    }
    if (amountMinorUnits != null &&
        (amountMinorUnits <= 0 || amountMinorUnits > maxAmountMinorUnits)) {
      throw ArgumentError.value(amountMinorUnits, 'amountMinorUnits');
    }
    final signed = amountMinorUnits == null
        ? t.amountMinorUnits
        : (t.amountMinorUnits < 0 ? -amountMinorUnits : amountMinorUnits);
    final name = merchant?.trim();
    final when = timestamp ?? t.transactionTimestamp;
    if (signed == t.amountMinorUnits &&
        when == t.transactionTimestamp &&
        (name == null || name.isEmpty || name == t.merchant)) {
      return;
    }
    final applied =
        t.transactionState == TransactionState.confirmed ||
        t.transactionState == TransactionState.reconciled;
    if (applied) {
      if (await _movesBalance(t)) {
        await db.accountsDao.adjustAccountBalance(
          t.physicalAccountId,
          -(t.appliedMinorUnits ?? t.amountMinorUnits),
        );
      }
      final spend = await _budgetSpend(t);
      final bucket = t.allocationBucketId ?? await _defaultExpenseBucketId();
      if (spend != 0 && bucket != null) {
        await db.accountsDao.recordBucketSpend(bucket, -spend);
      }
      await _markCategoryPaid(t, sign: -1);
    }
    await (db.update(
      db.transactions,
    )..where((x) => x.id.equals(transactionId))).write(
      TransactionsCompanion(
        amountMinorUnits: Value(signed),
        transactionTimestamp: Value(when),
        merchant: name == null || name.isEmpty
            ? const Value.absent()
            : Value(name.length > 120 ? name.substring(0, 120) : name),
      ),
    );
    if (!applied) return;
    final now = (await db.transactionsDao.getTransactionById(transactionId))!;
    var moved = 0;
    if (await _movesBalance(now)) {
      final before = await _balance(now.physicalAccountId);
      await db.accountsDao.adjustAccountBalance(
        now.physicalAccountId,
        now.amountMinorUnits,
      );
      moved = await _balance(now.physicalAccountId) - before;
    }
    await (db.update(db.transactions)..where((x) => x.id.equals(now.id))).write(
      TransactionsCompanion(appliedMinorUnits: Value(moved)),
    );
    final spend = await _budgetSpend(now);
    final bucket = now.allocationBucketId ?? await _defaultExpenseBucketId();
    if (spend != 0 && bucket != null) {
      await db.accountsDao.recordBucketSpend(bucket, spend);
    }
    await _markCategoryPaid(now, sign: 1);
  });

  /// Ids of entries Rivero creates in pairs (plan moves, card-bill legs,
  /// the cash side of an ATM withdrawal).
  static bool _pairedByApp(String id) =>
      id.startsWith('plan-') || id.startsWith('cc-') || id.startsWith('atm-');

  /// Whether [t] and its linked [partner] are accepted or ignored together:
  /// pairs Rivero made, and the two messages of one card bill (the bank's
  /// debit and the card's "payment received").
  static bool _decidedTogether(LedgerTransaction t, String partner) =>
      _pairedByApp(partner) ||
      _pairedByApp(t.id) ||
      (t.isInternalTransfer &&
          t.transactionType == TransactionType.creditCardSettlement);

  /// Deletes a transaction; if it is one leg of a transfer Rivero created
  /// (plan move, card bill), the other leg goes too so the two accounts
  /// never disagree.
  Future<void> removeWithPlanPartner(String transactionId) =>
      db.transaction(() async {
        final t = await db.transactionsDao.getTransactionById(transactionId);
        final partner = t?.linkedTransactionId;
        if (partner != null &&
            (_pairedByApp(transactionId) || _pairedByApp(partner))) {
          await remove(partner);
        }
        await remove(transactionId);
      });

  /// Moves a pending transaction to confirmed and applies its effects once.
  /// Safe against double taps: the state flips only once (a conditional
  /// update), and only the caller that flipped it applies the effects.
  /// Returns true when this call confirmed it.
  Future<bool> confirm(String transactionId) => db.transaction(() async {
    final t = await db.transactionsDao.getTransactionById(transactionId);
    if (t == null) return false;
    final flipped =
        await (db.update(db.transactions)..where(
              (x) =>
                  x.id.equals(transactionId) &
                  x.transactionState.isNotIn([
                    TransactionState.confirmed.name,
                    TransactionState.reconciled.name,
                  ]),
            ))
            .write(
              const TransactionsCompanion(
                transactionState: Value(TransactionState.confirmed),
              ),
            );
    if (flipped == 0) return false;
    await applyEffects(t);
    // The other leg of a card bill Rivero created goes with it.
    final partner = t.linkedTransactionId;
    if (partner != null && _decidedTogether(t, partner)) {
      await confirm(partner);
    }
    return true;
  });

  /// "Not a transaction": nothing is applied; a paired leg goes too.
  Future<void> ignore(String transactionId) => db.transaction(() async {
    final t = await db.transactionsDao.getTransactionById(transactionId);
    if (t == null) return;
    final applied =
        t.transactionState == TransactionState.confirmed ||
        t.transactionState == TransactionState.reconciled;
    if (applied) return; // Applied money is undone by deleting, not ignoring.
    // Already ignored: also what stops two linked legs calling each other.
    if (t.transactionState == TransactionState.ignored) return;
    await db.transactionsDao.updateTransactionState(
      transactionId,
      TransactionState.ignored,
    );
    final partner = t.linkedTransactionId;
    if (partner != null && _decidedTogether(t, partner)) {
      await ignore(partner);
    }
  });

  /// Whether [t] still has to move its account's balance: false when the
  /// balance was stated (typed in, or reported by the bank) at or after
  /// [t]'s time, because [t] is then already inside it.
  Future<bool> _movesBalance(LedgerTransaction t) async {
    final acc = await db.accountsDao.getPhysicalAccountById(
      t.physicalAccountId,
    );
    return acc == null || AccountsDao.movesBalance(acc, t.transactionTimestamp);
  }

  /// Applies balance and budget effects of [t]. Call exactly once, when the
  /// transaction becomes confirmed.
  Future<void> applyEffects(LedgerTransaction t) async {
    // An entry older than the account's last stated balance (an older
    // capture accepted late, a spend logged for yesterday) is already
    // inside that balance: it is recorded, but the balance stays.
    var applied = 0;
    if (await _movesBalance(t)) {
      final before = await _balance(t.physicalAccountId);
      await db.accountsDao.adjustAccountBalance(
        t.physicalAccountId,
        t.amountMinorUnits,
      );
      applied = await _balance(t.physicalAccountId) - before;
    }
    // Kept so deleting the entry undoes exactly this (see remove).
    await (db.update(db.transactions)..where((x) => x.id.equals(t.id))).write(
      TransactionsCompanion(appliedMinorUnits: Value(applied)),
    );
    if (await _cashFromAtm(t)) return; // moved to Cash: not spent yet
    await _markCategoryPaid(t, sign: 1);
    // Paying an autopay (captured or typed in) moves it to its next date,
    // so it is not reserved and spent at the same time.
    if (t.amountMinorUnits < 0 &&
        !t.isInternalTransfer &&
        _autopayTypes.contains(t.transactionType)) {
      await MandateTracker(db).onDebit(
        merchant: t.merchant,
        amountMinorUnits: -t.amountMinorUnits,
        at: t.transactionTimestamp,
      );
    }
    final spend = await _budgetSpend(t);
    if (spend == 0) return;
    final bucketId = t.allocationBucketId ?? await _defaultExpenseBucketId();
    if (bucketId != null) {
      await db.accountsDao.recordBucketSpend(bucketId, spend);
    }
  }

  Future<int> _balance(String accountId) async =>
      (await db.accountsDao.getPhysicalAccountById(accountId))
          ?.balanceMinorUnits ??
      0;

  /// Cash taken from an ATM goes into the Cash account when there is
  /// exactly one: a move between the user's own money, spent only when the
  /// cash is. Without a Cash account it stays a plain spend. Returns true
  /// when the cash side was recorded.
  Future<bool> _cashFromAtm(LedgerTransaction t) async {
    if (t.transactionType != TransactionType.atmWithdrawal ||
        t.amountMinorUnits >= 0 ||
        t.linkedTransactionId != null) {
      return false;
    }
    final cash = (await db.accountsDao.getAllActivePhysicalAccounts())
        .where(
          (a) =>
              a.accountType == StandardAccountTypes.cash &&
              !a.isLiability &&
              a.id != t.physicalAccountId,
        )
        .toList();
    if (cash.length != 1) return false;
    final id = 'atm-${t.id}';
    await db.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: Value(id),
        physicalAccountId: Value(cash.single.id),
        amountMinorUnits: Value(-t.amountMinorUnits),
        transactionType: const Value(TransactionType.internalTransfer),
        transactionState: const Value(TransactionState.confirmed),
        merchant: const Value('Cash withdrawn'),
        category: const Value('Cash'),
        transactionTimestamp: Value(t.transactionTimestamp),
        createdAt: Value(DateTime.now()),
        isInternalTransfer: const Value(true),
        linkedTransactionId: Value(t.id),
      ),
    );
    await (db.update(db.transactions)..where((x) => x.id.equals(t.id))).write(
      TransactionsCompanion(
        isInternalTransfer: const Value(true),
        linkedTransactionId: Value(id),
      ),
    );
    final leg = await db.transactionsDao.getTransactionById(id);
    if (leg != null) await applyEffects(leg);
    return true;
  }

  /// Turns two matched legs into an internal transfer (money moved between the
  /// user's own accounts): not an expense and not income. If the debit leg was
  /// already confirmed it had consumed budget, so that spend is given back.
  Future<void> convertToTransfer(
    LedgerTransaction debit,
    LedgerTransaction credit,
  ) => db.transaction(() async {
    final debitApplied =
        debit.transactionState == TransactionState.confirmed ||
        debit.transactionState == TransactionState.reconciled;
    if (debitApplied) {
      final spend = await _budgetSpend(debit);
      if (spend > 0) {
        final bucketId =
            debit.allocationBucketId ?? await _defaultExpenseBucketId();
        if (bucketId != null) {
          await db.accountsDao.recordBucketSpend(bucketId, -spend);
        }
      }
    }
    await db.transactionsDao.updateTransactionType(
      debit.id,
      TransactionType.internalTransfer,
    );
    await db.transactionsDao.updateTransactionType(
      credit.id,
      TransactionType.internalTransfer,
    );
  });

  static const Set<TransactionType> _categoryPayments = {
    TransactionType.planTransfer,
    TransactionType.investmentContribution,
    TransactionType.bucketFunding,
    TransactionType.internalTransfer,
  };

  /// A money-out leg tagged with a plan category (investments, savings,
  /// rent, family...) counts as that category being paid; undone on removal.
  /// The everyday spending budget is the allocation itself, never "paid".
  Future<void> _markCategoryPaid(
    LedgerTransaction t, {
    required int sign,
  }) async {
    final id = t.allocationBucketId;
    if (id == null ||
        t.amountMinorUnits >= 0 ||
        !_categoryPayments.contains(t.transactionType)) {
      return;
    }
    final b = await db.accountsDao.getBucketById(id);
    if (b == null || b.role == AccountRole.expense) return;
    await db.accountsDao.recordBucketSpend(id, sign * -t.amountMinorUnits);
  }

  /// Positive = budget consumed, negative = budget returned, 0 = no effect.
  Future<int> _budgetSpend(LedgerTransaction t) async {
    final account = await db.accountsDao.getPhysicalAccountById(
      t.physicalAccountId,
    );
    if (account == null || account.isLiability) return 0;
    // Cash moved into the Cash account (see _cashFromAtm) is not spent.
    if (t.isInternalTransfer &&
        t.transactionType == TransactionType.atmWithdrawal) {
      return 0;
    }
    final amount = t.amountMinorUnits;
    if (amount < 0 && _cashOutflows.contains(t.transactionType)) {
      return -amount;
    }
    if (amount < 0 &&
        t.transactionType == TransactionType.creditCardSettlement) {
      final reserve =
          await db.settingsDao.get(SettingKeys.reserveCreditCards) != '0';
      return reserve ? -amount : 0;
    }
    if (amount > 0 && t.transactionType == TransactionType.refund) {
      return -amount;
    }
    return 0;
  }

  Future<String?> _defaultExpenseBucketId() async {
    final buckets = await db.accountsDao
        .watchBucketsByRole(AccountRole.expense)
        .first;
    return buckets.isEmpty ? null : buckets.first.id;
  }
}
