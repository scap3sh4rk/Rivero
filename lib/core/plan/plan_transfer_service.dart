import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ledger/ledger_service.dart';

/// One payment the plan makes out of the salary account.
class PlannedMove {
  const PlannedMove({
    required this.bucketId,
    required this.name,
    required this.role,
    required this.amount,
    this.toAccountId,
  });

  final String bucketId;
  final String name;
  final AccountRole role;

  /// Minor units, > 0.
  final int amount;

  /// Account that receives the money, or null when it leaves the user's
  /// accounts (rent, family, an investment held outside Rivero).
  final String? toAccountId;
}

/// What the plan does to the accounts, in the owner's model:
///
///   salary lands in the SALARY ACCOUNT
///     - each fixed category is paid out of it (rent, SIP, family...)
///     - the spending share moves into the SPENDING ACCOUNT
///   so balances follow the plan, and the spending budget is exactly what
///   the spending account received this cycle (plus carry-over).
///
/// Entries have deterministic ids per cycle, so revising the plan adjusts
/// them instead of creating duplicates.
class PlanTransferService {
  PlanTransferService(this.db);

  final RiveroDatabase db;

  static const idPrefix = 'plan-';

  static String _key(DateTime cycleStart) =>
      '${cycleStart.year}${cycleStart.month.toString().padLeft(2, '0')}'
      '${cycleStart.day.toString().padLeft(2, '0')}';

  static String _prefix(DateTime cycleStart) => '$idPrefix${_key(cycleStart)}-';

  /// The salary account: the saved choice, else an account of type Salary,
  /// else the first non-card account.
  static PhysicalAccount? salaryAccountOf(
    List<PhysicalAccount> accounts,
    String? savedId,
  ) {
    final banks = accounts.where((a) => !a.isLiability).toList();
    return banks.where((a) => a.id == savedId).firstOrNull ??
        banks
            .where((a) => a.accountType == StandardAccountTypes.salary)
            .firstOrNull ??
        banks.firstOrNull;
  }

  /// The account everyday spending draws from: the spending bucket's linked
  /// account, else the salary account itself.
  static PhysicalAccount? spendingAccountOf(
    List<AllocationBucket> buckets,
    List<PhysicalAccount> accounts,
    PhysicalAccount? salary,
  ) {
    final linked = buckets
        .where((b) => b.role == AccountRole.expense)
        .map((b) => b.linkedPhysicalAccountId)
        .whereType<String>()
        .firstOrNull;
    return accounts
            .where((a) => a.id == linked && !a.isLiability)
            .firstOrNull ??
        salary;
  }

  /// The account a category most likely belongs in when none is chosen: the
  /// one investment account for an investment category, the one savings
  /// account for a savings category. Null when unclear (none, or several).
  static String? defaultDestination(
    AllocationBucket b,
    List<PhysicalAccount> accounts, {
    required String? salaryId,
    String? spendingId,
  }) {
    final type = switch (b.role) {
      AccountRole.investment => StandardAccountTypes.investment,
      AccountRole.savings => StandardAccountTypes.savings,
      _ => null,
    };
    if (type == null) return null;
    final hits = accounts
        .where(
          (a) =>
              !a.isLiability &&
              a.accountType == type &&
              a.id != salaryId &&
              a.id != spendingId,
        )
        .toList();
    return hits.length == 1 ? hits.single.id : null;
  }

  /// The moves that follow from [allocations] (bucket id -> amount): only
  /// transfers between accounts the user tracks in Rivero. A category with
  /// no destination account (rent, family) is "plan only": no numbers change
  /// until its real payment is recorded.
  List<PlannedMove> movesFor({
    required Map<String, int> allocations,
    required List<AllocationBucket> buckets,
    required PhysicalAccount salary,
    required PhysicalAccount? spending,
  }) {
    final moves = <PlannedMove>[];
    for (final b in buckets) {
      final amount = allocations[b.id] ?? 0;
      if (amount <= 0) continue;
      final String? dest;
      if (b.role == AccountRole.expense) {
        // Spending stays put when salary and spending are the same account.
        dest = spending != null && spending.id != salary.id
            ? spending.id
            : null;
      } else {
        final linked = b.linkedPhysicalAccountId;
        dest = linked != null && linked != salary.id ? linked : null;
      }
      if (dest == null) continue;
      moves.add(
        PlannedMove(
          bucketId: b.id,
          name: b.name,
          role: b.role,
          amount: amount,
          toAccountId: dest,
        ),
      );
    }
    return moves;
  }

  /// Categories the plan sets aside but does not move (no tracked account).
  List<PlannedMove> planOnly({
    required Map<String, int> allocations,
    required List<AllocationBucket> buckets,
    required PhysicalAccount salary,
  }) => [
    for (final b in buckets)
      if (b.role != AccountRole.expense &&
          (allocations[b.id] ?? 0) > 0 &&
          (b.linkedPhysicalAccountId == null ||
              b.linkedPhysicalAccountId == salary.id))
        PlannedMove(
          bucketId: b.id,
          name: b.name,
          role: b.role,
          amount: allocations[b.id]!,
        ),
  ];

  /// Whether this cycle already has plan entries (money has been moved).
  Future<bool> hasMoves(DateTime cycleStart) async {
    final prefix = _prefix(cycleStart);
    final all = await db.select(db.transactions).get();
    return all.any((t) => t.id.startsWith(prefix));
  }

  /// How far the salary account would go below zero if [moves] were made
  /// on top of today's balance (0 = it can afford them).
  static int shortfall(PhysicalAccount salary, List<PlannedMove> moves) {
    final out = moves.fold<int>(0, (s, m) => s + m.amount);
    final after = salary.balanceMinorUnits - out;
    return after < 0 ? -after : 0;
  }

  TransactionType _typeFor(AccountRole role) => switch (role) {
    AccountRole.investment => TransactionType.investmentContribution,
    AccountRole.savings => TransactionType.bucketFunding,
    _ => TransactionType.internalTransfer,
  };

  /// Makes this cycle's entries match [moves]: new ones are created,
  /// changed ones replaced, removed ones undone. Returns how many changed.
  Future<int> sync({
    required DateTime cycleStart,
    required PhysicalAccount salary,
    required List<PlannedMove> moves,
  }) async {
    final prefix = _prefix(cycleStart);
    final ledger = LedgerService(db);
    var changed = 0;

    await db.transaction(() async {
      final existing = (await db.select(db.transactions).get())
          .where((t) => t.id.startsWith(prefix))
          .toList();
      final wanted = {for (final m in moves) '$prefix${m.bucketId}': m};

      // Debit legs by bucket (credit legs share the id with '-in').
      for (final t in existing.where((t) => t.id.endsWith('-out'))) {
        final base = t.id.substring(0, t.id.length - '-out'.length);
        final move = wanted[base];
        final same =
            move != null &&
            t.amountMinorUnits == -move.amount &&
            t.physicalAccountId == salary.id;
        if (same) continue;
        await _undo(ledger, t);
        changed++;
      }

      final kept = (await db.select(db.transactions).get())
          .where((t) => t.id.startsWith(prefix))
          .map((t) => t.id)
          .toSet();
      for (final e in wanted.entries) {
        if (kept.contains('${e.key}-out')) continue;
        await _create(ledger, e.key, e.value, salary);
        changed++;
      }
    });
    return changed;
  }

  Future<void> _undo(LedgerService ledger, LedgerTransaction out) async {
    final partner = out.linkedTransactionId;
    // Remove the destination leg first, then the debit.
    if (partner != null) await ledger.remove(partner);
    await ledger.remove(out.id);
  }

  Future<void> _create(
    LedgerService ledger,
    String base,
    PlannedMove m,
    PhysicalAccount salary,
  ) async {
    final now = DateTime.now();
    final type = _typeFor(m.role);
    // Reads in Activity as "from <salary account> to <destination>".
    final dest = m.toAccountId == null
        ? null
        : await db.accountsDao.getPhysicalAccountById(m.toAccountId!);
    final label = 'Transfer: ${salary.name} → ${dest?.name ?? 'account'}';
    final outId = '$base-out';
    final inId = '$base-in';

    await db.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: Value(outId),
        physicalAccountId: Value(salary.id),
        allocationBucketId: Value(m.bucketId),
        amountMinorUnits: Value(-m.amount),
        transactionType: Value(type),
        transactionState: const Value(TransactionState.confirmed),
        merchant: Value(label),
        category: Value(m.name),
        transactionTimestamp: Value(now),
        createdAt: Value(now),
        isInternalTransfer: Value(m.toAccountId != null),
        linkedTransactionId: Value(m.toAccountId != null ? inId : null),
      ),
    );
    final out = await db.transactionsDao.getTransactionById(outId);
    if (out != null) await ledger.applyEffects(out);

    if (m.toAccountId != null) {
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: Value(inId),
          physicalAccountId: Value(m.toAccountId!),
          allocationBucketId: Value(m.bucketId),
          amountMinorUnits: Value(m.amount),
          transactionType: Value(type),
          transactionState: const Value(TransactionState.confirmed),
          merchant: Value(label),
          category: Value(m.name),
          transactionTimestamp: Value(now),
          createdAt: Value(now),
          isInternalTransfer: const Value(true),
          linkedTransactionId: Value(outId),
        ),
      );
      final inn = await db.transactionsDao.getTransactionById(inId);
      if (inn != null) await ledger.applyEffects(inn);
    }
  }

  /// Saves which account salary lands in.
  Future<void> setSalaryAccount(String accountId) =>
      db.settingsDao.set(SettingKeys.salaryAccount, accountId);
}
