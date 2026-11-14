import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/engine/allocation_rule.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/engine/waterfall_allocator.dart';
import 'package:rivero/core/plan/plan_transfer_service.dart';

/// A user-facing validation problem (shown as a message, not a crash).
class PlanValidationException implements Exception {
  const PlanValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

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

  /// What an expense bucket would carry into the next cycle: its unspent
  /// money (never negative; an overspend is not carried as debt).
  static int carryFor(AllocationBucket b) => b.role == AccountRole.expense
      ? (b.allocatedMinorUnits + b.carryOverMinorUnits - b.spentMinorUnits)
            .clamp(0, 1 << 62)
      : 0;

  /// Writes [allocations] into the buckets and starts a fresh cycle (spend
  /// resets). Unspent expense money is carried over when [carryOver]. When
  /// [rememberAsDefault], non-expense amounts become the new monthly targets.
  /// Throws if the split exceeds [salary].
  Future<void> apply({
    required int salary,
    required Map<String, int> allocations,
    String? salaryTransactionId,
    DateTime? cycleStart,
    bool rememberAsDefault = true,
    bool carryOver = true,
    bool? moveMoney,
    bool alreadyMoved = false,
  }) async {
    final total = allocations.values.fold<int>(0, (a, b) => a + b);
    if (allocations.values.any((v) => v < 0) || total > salary) {
      throw ArgumentError(
        'Allocations must be non-negative and fit the salary',
      );
    }
    final buckets = await db.accountsDao.getAllBuckets();
    final now = DateTime.now();
    // Editing the plan inside the pay cycle it was made for is a revision,
    // not a new month: spending so far and the carry-in stay as they were.
    // Only a plan for a later cycle carries unspent money forward.
    final raw = await db.settingsDao.get(SettingKeys.lastPlannedCycleStart);
    final lastPlanned = raw == null ? null : DateTime.tryParse(raw);
    final sameCycle =
        cycleStart != null &&
        lastPlanned != null &&
        lastPlanned.isAtSameMomentAs(cycleStart);
    await db.transaction(() async {
      for (final b in buckets) {
        final amount = allocations[b.id] ?? 0;
        await db.accountsDao.upsertBucket(
          AllocationBucketsCompanion(
            id: Value(b.id),
            name: Value(b.name),
            role: Value(b.role),
            allocatedMinorUnits: Value(amount),
            carryOverMinorUnits: Value(
              sameCycle ? b.carryOverMinorUnits : (carryOver ? carryFor(b) : 0),
            ),
            spentMinorUnits: Value(sameCycle ? b.spentMinorUnits : 0),
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
      if (cycleStart != null) {
        await db.settingsDao.set(
          SettingKeys.lastPlannedCycleStart,
          cycleStart.toIso8601String(),
        );
      }
      // Money moves when a salary credit is being split, or when this
      // cycle's money has already moved and the plan is being revised.
      final transfers = PlanTransferService(db);
      // Spending with no account chosen draws from the salary account, so
      // Safe to spend follows a real balance from the very first plan.
      final everyAccount = await db.accountsDao.getAllActivePhysicalAccounts();
      final home = PlanTransferService.salaryAccountOf(
        everyAccount,
        await db.settingsDao.get(SettingKeys.salaryAccount),
      );
      if (home != null) {
        await (db.update(db.allocationBuckets)..where(
              (t) =>
                  t.role.equals(AccountRole.expense.name) &
                  t.linkedPhysicalAccountId.isNull(),
            ))
            .write(
              AllocationBucketsCompanion(
                linkedPhysicalAccountId: Value(home.id),
              ),
            );
      }
      // Already told "this month's money already moved": never again.
      final movedOutside =
          cycleStart != null &&
          await db.settingsDao.get(SettingKeys.planMovedOutside) ==
              cycleKey(cycleStart);
      if (alreadyMoved && cycleStart != null) {
        await db.settingsDao.set(
          SettingKeys.planMovedOutside,
          cycleKey(cycleStart),
        );
      }
      final skipMoves = alreadyMoved || movedOutside;
      final move =
          cycleStart != null &&
          (skipMoves ||
              (moveMoney ??
                  (salaryTransactionId != null ||
                      await transfers.hasMoves(cycleStart))));
      if (move) {
        final accounts = await db.accountsDao.getAllActivePhysicalAccounts();
        final salary = PlanTransferService.salaryAccountOf(
          accounts,
          await db.settingsDao.get(SettingKeys.salaryAccount),
        );
        if (salary != null) {
          final fresh = await db.accountsDao.getAllBuckets();
          final moves = transfers.movesFor(
            allocations: allocations,
            buckets: fresh,
            salary: salary,
            spending: PlanTransferService.spendingAccountOf(
              fresh,
              accounts,
              salary,
            ),
          );
          if (skipMoves) {
            // Set up mid-month: the money moved before Rivero knew, and the
            // balances entered already show it. Record it as done, move
            // nothing.
            for (final m in moves) {
              if (m.role != AccountRole.expense) {
                await markAlreadyPaid(m.bucketId);
              }
            }
          } else {
            // A bank account never goes below zero because of the plan.
            final extra =
                moves.fold<int>(0, (t, m) => t + m.amount) -
                await transfers.movedOut(cycleStart);
            if (extra > 0 && salary.balanceMinorUnits < extra) {
              throw PlanValidationException(
                '${salary.name} holds less than the plan moves. If this '
                "month's money already moved, choose \"Already moved\".",
              );
            }
            await transfers.sync(
              cycleStart: cycleStart,
              salary: salary,
              moves: moves,
            );
          }
        }
      }
    });
  }

  /// yyyy-mm-dd of a cycle start (the key stored for "already moved").
  static String cycleKey(DateTime start) =>
      '${start.year}-${start.month}-${start.day}';

  /// Whether this cycle's plan money was marked as moved before Rivero.
  Future<bool> movedOutside(DateTime cycleStart) async =>
      await db.settingsDao.get(SettingKeys.planMovedOutside) ==
      cycleKey(cycleStart);

  /// The cycle a salary credited at [credited] belongs to: one that lands
  /// up to 5 days before pay day (weekend, holiday) is next cycle's salary.
  static DateTime cycleForSalary(Paycycle current, DateTime credited) =>
      credited.isBefore(
        current.nextCycleStartDate.subtract(const Duration(days: 5)),
      )
      ? current.cycleStartDate
      : current.nextCycleStartDate;

  /// Pay day moved: this month's plan (and the money it moved) stays this
  /// month's plan under the new cycle start, instead of looking like a new
  /// month that resets spending and carry-over.
  Future<void> moveCycle({required DateTime from, required DateTime to}) =>
      db.transaction(() async {
        if (from.isAtSameMomentAs(to)) return;
        final raw = await db.settingsDao.get(SettingKeys.lastPlannedCycleStart);
        final last = raw == null ? null : DateTime.tryParse(raw);
        if (last == null || !last.isAtSameMomentAs(from)) return;
        await db.settingsDao.set(
          SettingKeys.lastPlannedCycleStart,
          to.toIso8601String(),
        );
        if (await db.settingsDao.get(SettingKeys.planMovedOutside) ==
            cycleKey(from)) {
          await db.settingsDao.set(SettingKeys.planMovedOutside, cycleKey(to));
        }
        await PlanTransferService(db).rekey(from, to);
      });

  /// Marks categories paid this cycle without touching any balance: the
  /// money left the accounts before Rivero was set up (mid-month start).
  Future<void> markAlreadyPaid(String bucketId) async {
    final b = await db.accountsDao.getBucketById(bucketId);
    if (b == null) return;
    await (db.update(
      db.allocationBuckets,
    )..where((t) => t.id.equals(bucketId))).write(
      AllocationBucketsCompanion(spentMinorUnits: Value(b.allocatedMinorUnits)),
    );
  }

  /// True when a new pay cycle has started but its salary was not split yet.
  Future<bool> awaitingSalary(DateTime cycleStart) async {
    final raw = await db.settingsDao.get(SettingKeys.lastPlannedCycleStart);
    final last = raw == null ? null : DateTime.tryParse(raw);
    return last != null && last.isBefore(cycleStart);
  }

  /// Saves where money goes: the spending account, and for set-aside
  /// categories an optional destination account (null = paid outside Rivero).
  Future<void> setRouting({
    String? spendingAccountId,
    Map<String, String?> destinations = const {},
  }) async {
    final buckets = await db.accountsDao.getAllBuckets();
    for (final b in buckets) {
      String? link;
      if (b.role == AccountRole.expense) {
        if (spendingAccountId == null) continue;
        link = spendingAccountId;
      } else if (destinations.containsKey(b.id)) {
        link = destinations[b.id];
      } else {
        continue;
      }
      await (db.update(
        db.allocationBuckets,
      )..where((t) => t.id.equals(b.id))).write(
        AllocationBucketsCompanion(linkedPhysicalAccountId: Value(link)),
      );
    }
  }

  /// Adds a user category (e.g. Rent, Family) funded from salary each month.
  /// Returns the new bucket id. Rejects blank or duplicate names.
  Future<String> addCustomCategory(String name, int monthlyAmount) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 100) {
      throw const PlanValidationException('Give the category a name');
    }
    if (monthlyAmount < 0) {
      throw const PlanValidationException('Amount cannot be negative');
    }
    final buckets = await db.accountsDao.getAllBuckets();
    if (buckets.any((b) => b.name.toLowerCase() == clean.toLowerCase())) {
      throw PlanValidationException('"$clean" already exists');
    }
    final now = DateTime.now();
    final id = 'bucket-${now.microsecondsSinceEpoch}';
    final order =
        buckets.fold<int>(
          0,
          (m, b) => b.priorityOrder > m ? b.priorityOrder : m,
        ) +
        1;
    await db.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: Value(id),
        name: Value(clean),
        role: const Value(AccountRole.custom),
        targetMinorUnits: Value(monthlyAmount),
        // Null = paid outside Rivero (rent, family); set a destination
        // account to have the money arrive there too.
        linkedPhysicalAccountId: const Value(null),
        priorityOrder: Value(order),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return id;
  }

  /// Removes a user category. Default buckets (expense / investment / savings)
  /// stay; past transactions keep their history (bucket link set to null).
  Future<void> removeCategory(String bucketId) async {
    final b = await db.accountsDao.getBucketById(bucketId);
    if (b == null || b.role != AccountRole.custom) return;
    await db.accountsDao.deleteBucket(bucketId);
  }

  /// Latest confirmed salary-like credit in this cycle not yet split, or null.
  /// Credits count when they are income of at least half the expected salary
  /// (or mention "salary").
  Future<LedgerTransaction?> pendingSalary({
    required DateTime cycleStart,
    required int expectedSalary,
  }) async {
    final lastId = await db.settingsDao.get(SettingKeys.lastPlannedSalaryTxn);
    // This cycle's salary was already split: a later big credit (bonus,
    // refund, money from a friend) is only offered if the bank calls it
    // salary.
    final raw = await db.settingsDao.get(SettingKeys.lastPlannedCycleStart);
    final planned = raw == null ? null : DateTime.tryParse(raw);
    final alreadySplit = planned != null && !planned.isBefore(cycleStart);
    final since = cycleStart.subtract(const Duration(days: 5));
    final all =
        await (db.select(db.transactions)..where(
              (t) =>
                  t.transactionType.equals(TransactionType.income.name) &
                  t.transactionTimestamp.isBiggerOrEqualValue(since),
            ))
            .get();
    final candidates =
        all.where((t) {
          if (t.transactionType != TransactionType.income) return false;
          if (t.transactionState != TransactionState.confirmed) return false;
          if (t.amountMinorUnits <= 0 || t.id == lastId) return false;
          if (t.isInternalTransfer) return false;
          // Salaries often land a day or two early (weekends, holidays).
          if (t.transactionTimestamp.isBefore(
            cycleStart.subtract(const Duration(days: 5)),
          )) {
            return false;
          }
          final looksLikeSalary = '${t.merchant} ${t.category}'
              .toLowerCase()
              .contains('salary');
          return looksLikeSalary ||
              (!alreadySplit &&
                  expectedSalary > 0 &&
                  t.amountMinorUnits * 2 >= expectedSalary);
        }).toList()..sort(
          (a, b) => b.transactionTimestamp.compareTo(a.transactionTimestamp),
        );
    return candidates.firstOrNull;
  }
}
