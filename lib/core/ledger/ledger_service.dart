import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/mandate_tracker.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ingestion/parser/financial_parser.dart';

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
      await db.accountsDao.adjustAccountBalance(
        t.physicalAccountId,
        -t.amountMinorUnits,
      );
      final spend = await _budgetSpend(t);
      if (spend != 0) {
        final bucketId =
            t.allocationBucketId ?? await _defaultExpenseBucketId();
        if (bucketId != null) {
          await db.accountsDao.recordBucketSpend(bucketId, -spend);
        }
      }
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

  /// Ids of entries Rivero creates in pairs (plan moves, card-bill legs).
  static bool _pairedByApp(String id) =>
      id.startsWith('plan-') || id.startsWith('cc-');

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
    if (partner != null && (_pairedByApp(partner) || _pairedByApp(t.id))) {
      await confirm(partner);
    }
    await _adoptReportedBalance(t);
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
    await db.transactionsDao.updateTransactionState(
      transactionId,
      TransactionState.ignored,
    );
    final partner = t.linkedTransactionId;
    if (partner != null && (_pairedByApp(partner) || _pairedByApp(t.id))) {
      await ignore(partner);
    }
  });

  /// A confirmed capture's bank message said "Avl bal": that is the truth
  /// for the account, unless something newer has happened there since.
  Future<void> _adoptReportedBalance(LedgerTransaction t) async {
    final logId = t.ingestionLogId;
    if (logId == null) return;
    final log = await (db.select(
      db.rawIngestionLogs,
    )..where((l) => l.id.equals(logId))).getSingleOrNull();
    if (log == null) return;
    final reported = const FinancialParser()
        .parse(
          RawNotification(
            id: log.id,
            body: log.rawPayload,
            receivedAt: log.receivedAt,
            sender: log.senderHeader,
          ),
        )
        ?.balanceMinorUnits;
    if (reported == null) return;
    final acc = await db.accountsDao.getPhysicalAccountById(
      t.physicalAccountId,
    );
    if (acc == null || acc.isLiability) return;
    final newer =
        await (db.select(db.transactions)..where(
              (x) =>
                  x.physicalAccountId.equals(t.physicalAccountId) &
                  x.id.equals(t.id).not() &
                  x.transactionTimestamp.isBiggerThanValue(
                    t.transactionTimestamp,
                  ) &
                  x.transactionState.isIn([
                    TransactionState.confirmed.name,
                    TransactionState.reconciled.name,
                  ]),
            ))
            .get();
    if (newer.isNotEmpty) return;
    await db.accountsDao.updateAccountBalance(t.physicalAccountId, reported);
  }

  /// Applies balance and budget effects of [t]. Call exactly once, when the
  /// transaction becomes confirmed.
  Future<void> applyEffects(LedgerTransaction t) async {
    await db.accountsDao.adjustAccountBalance(
      t.physicalAccountId,
      t.amountMinorUnits,
    );
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
