import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/engine/allocation_rule.dart';
import 'package:rivero/core/engine/waterfall_allocator.dart';

/// Turns the user's buckets into a monthly split and applies it when salary
/// arrives. Non-expense buckets get their fixed monthly target in priority
/// order; the expense bucket takes whatever is left.
class SalaryPlanService {
  SalaryPlanService(this.db, {this.allocator = const WaterfallAllocator()});

  final RiveroDatabase db;
  final WaterfallAllocator allocator;

  static const int _expensePriority = 1 << 20;

  List<AllocationRule> rulesFor(List<AllocationBucket> buckets) {
    return [
      for (final b in buckets)
        if (b.role == AccountRole.expense)
          AllocationRule(
            id: 'rule-${b.id}',
            bucketId: b.id,
            type: AllocationType.percentageOfRemaining,
            percentage: 100,
            priority: _expensePriority,
            isMandatory: false,
          )
        else if ((b.targetMinorUnits ?? 0) > 0)
          AllocationRule(
            id: 'rule-${b.id}',
            bucketId: b.id,
            type: AllocationType.fixed,
            fixedAmount: b.targetMinorUnits,
            priority: b.priorityOrder,
          ),
    ];
  }

  /// bucketId -> minor units for [salary], never exceeding the salary.
  Map<String, int> preview(int salary, List<AllocationBucket> buckets) =>
      allocator
          .allocate(salaryReceived: salary, rules: rulesFor(buckets))
          .allocations;

  /// Writes [allocations] into the buckets and starts a fresh cycle (spend
  /// resets). When [rememberAsDefault], non-expense amounts become the new
  /// monthly targets. Throws if the split exceeds [salary].
  Future<void> apply({
    required int salary,
    required Map<String, int> allocations,
    String? salaryTransactionId,
    bool rememberAsDefault = true,
  }) async {
    final total = allocations.values.fold<int>(0, (a, b) => a + b);
    if (allocations.values.any((v) => v < 0) || total > salary) {
      throw ArgumentError(
        'Allocations must be non-negative and fit the salary',
      );
    }
    final buckets = await db.accountsDao.getAllBuckets();
    final now = DateTime.now();
    await db.transaction(() async {
      for (final b in buckets) {
        final amount = allocations[b.id] ?? 0;
        await db.accountsDao.upsertBucket(
          AllocationBucketsCompanion(
            id: Value(b.id),
            name: Value(b.name),
            role: Value(b.role),
            allocatedMinorUnits: Value(amount),
            spentMinorUnits: const Value(0),
            targetMinorUnits: rememberAsDefault && b.role != AccountRole.expense
                ? Value(amount)
                : Value(b.targetMinorUnits),
            linkedPhysicalAccountId: Value(b.linkedPhysicalAccountId),
            priorityOrder: Value(b.priorityOrder),
            createdAt: Value(b.createdAt),
            updatedAt: Value(now),
          ),
        );
      }
      if (salaryTransactionId != null) {
        await db.settingsDao.set(
          SettingKeys.lastPlannedSalaryTxn,
          salaryTransactionId,
        );
      }
    });
  }

  /// Latest confirmed salary-like credit in this cycle not yet split, or null.
  /// Credits count when they are income of at least half the expected salary
  /// (or mention "salary").
  Future<LedgerTransaction?> pendingSalary({
    required DateTime cycleStart,
    required int expectedSalary,
  }) async {
    final lastId = await db.settingsDao.get(SettingKeys.lastPlannedSalaryTxn);
    final all = await db.transactionsDao.getAllTransactions();
    final candidates =
        all.where((t) {
          if (t.transactionType != TransactionType.income) return false;
          if (t.transactionState != TransactionState.confirmed) return false;
          if (t.amountMinorUnits <= 0 || t.id == lastId) return false;
          if (t.transactionTimestamp.isBefore(cycleStart)) return false;
          final looksLikeSalary = '${t.merchant} ${t.category}'
              .toLowerCase()
              .contains('salary');
          return looksLikeSalary ||
              (expectedSalary > 0 && t.amountMinorUnits * 2 >= expectedSalary);
        }).toList()..sort(
          (a, b) => b.transactionTimestamp.compareTo(a.transactionTimestamp),
        );
    return candidates.firstOrNull;
  }
}
