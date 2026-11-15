import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/tables/allocation_buckets_table.dart';
import 'package:rivero/core/database/tables/physical_accounts_table.dart';
import 'package:rivero/core/domain/account_role.dart';

part 'accounts_dao.g.dart';

/// Data Access Object for physical accounts and virtual allocation buckets.
@DriftAccessor(tables: [PhysicalAccounts, AllocationBuckets])
class AccountsDao extends DatabaseAccessor<RiveroDatabase>
    with _$AccountsDaoMixin {
  AccountsDao(super.attachedDatabase);

  // --- Physical Accounts ---

  /// Watch all active physical accounts ordered by institution and name.
  Stream<List<PhysicalAccount>> watchActivePhysicalAccounts() {
    return (select(physicalAccounts)
          ..where((tbl) => tbl.isActive.equals(true))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.institution),
            (t) => OrderingTerm(expression: t.name),
          ]))
        .watch();
  }

  /// Saves a new order: [orderedIds] get positions 0, 1, 2...
  Future<void> reorderAccounts(List<String> orderedIds) =>
      transaction(() async {
        for (var i = 0; i < orderedIds.length; i++) {
          await (update(physicalAccounts)
                ..where((t) => t.id.equals(orderedIds[i])))
              .write(PhysicalAccountsCompanion(sortOrder: Value(i)));
        }
      });

  /// Get all active physical accounts.
  Future<List<PhysicalAccount>> getAllActivePhysicalAccounts() {
    return (select(
      physicalAccounts,
    )..where((tbl) => tbl.isActive.equals(true))).get();
  }

  /// Find a physical account by its exact ID.
  Future<PhysicalAccount?> getPhysicalAccountById(String id) {
    return (select(
      physicalAccounts,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  /// Find a physical account by institution and account mask (e.g. "HDFC", "••4012").
  Future<PhysicalAccount?> findAccountByMask(
    String institution,
    String accountMask,
  ) {
    return (select(physicalAccounts)..where(
          (tbl) =>
              tbl.institution.equals(institution) &
              tbl.accountMask.equals(accountMask) &
              tbl.isActive.equals(true),
        ))
        .getSingleOrNull();
  }

  /// Insert or replace a physical account.
  Future<int> upsertPhysicalAccount(PhysicalAccountsCompanion account) {
    return into(physicalAccounts).insertOnConflictUpdate(account);
  }

  /// Update the balance of a physical account (in integer minor units / paise).
  Future<bool> updateAccountBalance(
    String accountId,
    int newBalanceMinorUnits,
  ) async {
    // A bank, wallet or cash balance never goes below zero (cards and loans,
    // which are debts, are stored as negative amounts owed).
    final acc = await getPhysicalAccountById(accountId);
    final floored = acc != null && !acc.isLiability && newBalanceMinorUnits < 0
        ? 0
        : newBalanceMinorUnits;
    final updatedRows =
        await (update(
          physicalAccounts,
        )..where((tbl) => tbl.id.equals(accountId))).write(
          PhysicalAccountsCompanion(
            balanceMinorUnits: Value(floored),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return updatedRows > 0;
  }

  /// The balance is known to be [balanceMinorUnits] as of [asOf] (typed by
  /// the user, or reported by the bank). See `balanceAsOf`.
  Future<void> setKnownBalance(
    String accountId,
    int balanceMinorUnits,
    DateTime asOf,
  ) async {
    await updateAccountBalance(accountId, balanceMinorUnits);
    await (update(physicalAccounts)..where((a) => a.id.equals(accountId)))
        .write(PhysicalAccountsCompanion(balanceAsOf: Value(asOf)));
  }

  /// Whether an entry dated [at] still has to move [account]'s balance
  /// (false when the balance was stated after that moment). Times are kept
  /// to the second, so an entry in the very second of the statement counts
  /// as new: that is the entry that brought the statement.
  static bool movesBalance(PhysicalAccount account, DateTime at) {
    final known = account.balanceAsOf;
    return known == null || !at.isBefore(known);
  }

  /// Adjust account balance by an offset (positive for credit, negative for debit).
  Future<bool> adjustAccountBalance(
    String accountId,
    int deltaMinorUnits,
  ) async {
    // One SQL statement, so two writers can never lose each other's change.
    // One SQL statement, so two writers can never lose each other's change.
    // Money accounts floor at zero; debts (cards, loans) may go negative.
    final rows = await customUpdate(
      'UPDATE physical_accounts SET balance_minor_units = '
      'CASE WHEN is_liability = 0 AND balance_minor_units + ? < 0 THEN 0 '
      'ELSE balance_minor_units + ? END, updated_at = ? WHERE id = ?',
      variables: [
        Variable.withInt(deltaMinorUnits),
        Variable.withInt(deltaMinorUnits),
        Variable.withDateTime(DateTime.now()),
        Variable.withString(accountId),
      ],
      updates: {physicalAccounts},
    );
    return rows > 0;
  }

  /// Deactivate (soft delete) a physical account.
  Future<bool> deactivatePhysicalAccount(String accountId) async {
    // Cards must not count on a hidden account to pay their bills.
    await (update(
      physicalAccounts,
    )..where((a) => a.billsPaidFromAccountId.equals(accountId))).write(
      const PhysicalAccountsCompanion(billsPaidFromAccountId: Value(null)),
    );
    // Plan categories must not keep routing money into a hidden account.
    await (update(
      allocationBuckets,
    )..where((b) => b.linkedPhysicalAccountId.equals(accountId))).write(
      const AllocationBucketsCompanion(linkedPhysicalAccountId: Value(null)),
    );
    final updatedRows =
        await (update(
          physicalAccounts,
        )..where((tbl) => tbl.id.equals(accountId))).write(
          PhysicalAccountsCompanion(
            isActive: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return updatedRows > 0;
  }

  /// Permanently delete a physical account.
  Future<int> deletePhysicalAccountPermanently(String accountId) {
    return (delete(
      physicalAccounts,
    )..where((tbl) => tbl.id.equals(accountId))).go();
  }

  // --- Allocation Buckets ---

  /// Watch all virtual allocation buckets ordered by priority.
  Stream<List<AllocationBucket>> watchAllBuckets() {
    return (select(
      allocationBuckets,
    )..orderBy([(t) => OrderingTerm(expression: t.priorityOrder)])).watch();
  }

  /// Watch buckets for a specific account role (e.g. EXPENSE, INVESTMENT).
  Stream<List<AllocationBucket>> watchBucketsByRole(AccountRole role) {
    return (select(allocationBuckets)
          ..where((tbl) => tbl.role.equals(role.name))
          ..orderBy([(t) => OrderingTerm(expression: t.priorityOrder)]))
        .watch();
  }

  /// One-shot read of every bucket.
  Future<List<AllocationBucket>> getAllBuckets() =>
      select(allocationBuckets).get();

  /// One-shot read of buckets for [role], highest priority first.
  Future<List<AllocationBucket>> getBucketsByRole(AccountRole role) {
    return (select(allocationBuckets)
          ..where((tbl) => tbl.role.equals(role.name))
          ..orderBy([(t) => OrderingTerm(expression: t.priorityOrder)]))
        .get();
  }

  /// Get allocation bucket by its exact ID.
  Future<AllocationBucket?> getBucketById(String id) {
    return (select(
      allocationBuckets,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  /// Insert or update an allocation bucket.
  Future<int> upsertBucket(AllocationBucketsCompanion bucket) {
    return into(allocationBuckets).insertOnConflictUpdate(bucket);
  }

  /// Record spending from an allocation bucket.
  Future<bool> recordBucketSpend(
    String bucketId,
    int deltaSpendMinorUnits,
  ) async {
    final rows = await customUpdate(
      'UPDATE allocation_buckets SET spent_minor_units = '
      'spent_minor_units + ?, updated_at = ? WHERE id = ?',
      variables: [
        Variable.withInt(deltaSpendMinorUnits),
        Variable.withDateTime(DateTime.now()),
        Variable.withString(bucketId),
      ],
      updates: {allocationBuckets},
    );
    return rows > 0;
  }

  /// Delete an allocation bucket.
  Future<int> deleteBucket(String bucketId) {
    return (delete(
      allocationBuckets,
    )..where((tbl) => tbl.id.equals(bucketId))).go();
  }

  /// Reset allocations for a new paycycle.
  Future<void> resetBucketsForNewCycle() async {
    await update(allocationBuckets).write(
      AllocationBucketsCompanion(
        spentMinorUnits: const Value(0),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
