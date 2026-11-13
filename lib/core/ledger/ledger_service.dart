import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

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

  static const Set<TransactionType> _cashOutflows = {
    TransactionType.expense,
    TransactionType.atmWithdrawal,
    TransactionType.cashExpenditure,
  };

  /// Records a user-entered transaction as confirmed and applies its effects.
  /// [amountMinorUnits] is signed (negative = money out).
  Future<void> recordManual({
    required String accountId,
    required int amountMinorUnits,
    required TransactionType type,
    required String merchant,
    required String category,
    String? bucketId,
  }) async {
    final now = DateTime.now();
    final id = 'txn-manual-${now.microsecondsSinceEpoch}';
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
        transactionTimestamp: Value(now),
        createdAt: Value(now),
      ),
    );
    final saved = await db.transactionsDao.getTransactionById(id);
    if (saved != null) await applyEffects(saved);
  }

  /// Moves a pending transaction to confirmed and applies its effects once.
  Future<void> confirm(String transactionId) async {
    final t = await db.transactionsDao.getTransactionById(transactionId);
    if (t == null) return;
    final applied =
        t.transactionState == TransactionState.confirmed ||
        t.transactionState == TransactionState.reconciled;
    if (applied) return;
    await db.transactionsDao.updateTransactionState(
      transactionId,
      TransactionState.confirmed,
    );
    await applyEffects(t);
  }

  /// Applies balance and budget effects of [t]. Call exactly once, when the
  /// transaction becomes confirmed.
  Future<void> applyEffects(LedgerTransaction t) async {
    await db.accountsDao.adjustAccountBalance(
      t.physicalAccountId,
      t.amountMinorUnits,
    );
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
  ) async {
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
