import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';

/// Everything behind the Safe-to-Spend number, in the order it is used.
/// The Home card and the "how is this calculated" sheet both read this, so
/// they can never disagree.
///
///   budget left = planned + carried over − spent
///   safe to spend = budget left − autopay due − card bills (+ owed to you)
///   per day = safe to spend ÷ days to payday
class StsBreakdown {
  const StsBreakdown({
    required this.planned,
    required this.carriedOver,
    required this.spent,
    required this.mandates,
    required this.mandatesTotal,
    required this.cardBills,
    required this.owedToYou,
    required this.owedIncluded,
    required this.setAside,
    required this.spendingAccountBalance,
    required this.daysToPayday,
    required this.result,
  });
  factory StsBreakdown.compute({
    required List<AllocationBucket> buckets,
    required List<PhysicalAccount> accounts,
    required List<Mandate> mandates,
    required List<Due> dues,
    required Paycycle cycle,
    required bool reserveCards,
    required bool includeOwed,
    DateTime? now,
    DateTime? lastSyncedAt,
    SafeToSpendCalculator calculator = const SafeToSpendCalculator(),
  }) {
    final at = now ?? DateTime.now();
    final spending = buckets.where((b) => b.role == AccountRole.expense);
    final planned = spending.fold<int>(0, (s, b) => s + b.allocatedMinorUnits);
    final carried = spending.fold<int>(0, (s, b) => s + b.carryOverMinorUnits);
    final spent = spending.fold<int>(0, (s, b) => s + b.spentMinorUnits);
    final setAside = buckets
        .where((b) => b.role != AccountRole.expense)
        .fold<int>(0, (s, b) => s + b.allocatedMinorUnits);

    final due = upcomingMandates(mandates, at, cycle.cycleEndDate);
    final dueTotal = due.fold<int>(0, (s, m) => s + mandateReserve(m));

    final cards = reserveCards
        ? accounts
              .where((a) => a.isLiability && a.balanceMinorUnits < 0)
              .fold<int>(0, (s, a) => s - a.balanceMinorUnits)
        : 0;
    final owed = DuesService.totalOutstanding(dues);

    final linked = spending
        .map((b) => b.linkedPhysicalAccountId)
        .whereType<String>()
        .toSet();
    final linkedAccounts = accounts.where(
      (a) => linked.contains(a.id) && !a.isLiability,
    );
    final accountBalance = linkedAccounts.isEmpty
        ? null
        : linkedAccounts.fold<int>(0, (s, a) => s + a.balanceMinorUnits);

    final result = calculator.calculate(
      expenseBalance: planned + carried - spent,
      upcomingMandates: dueTotal,
      unsettledCreditCardLiability: cards,
      pendingReimbursements: owed,
      daysRemainingInCycle: cycle.daysRemaining,
      lastSyncedAt: lastSyncedAt ?? at,
      asOf: at,
      includePendingReimbursements: includeOwed,
    );

    return StsBreakdown(
      planned: planned,
      carriedOver: carried,
      spent: spent,
      mandates: due,
      mandatesTotal: dueTotal,
      cardBills: cards,
      owedToYou: owed,
      owedIncluded: includeOwed,
      setAside: setAside,
      spendingAccountBalance: accountBalance,
      daysToPayday: result.daysRemainingInCycle,
      result: result,
    );
  }

  /// Planned for spending this cycle (salary minus what is set aside).
  final int planned;
  final int carriedOver;
  final int spent;

  /// Autopays still due before payday, soonest first.
  final List<Mandate> mandates;
  final int mandatesTotal;

  /// Unpaid card spend reserved (0 when the card toggle is off).
  final int cardBills;
  final int owedToYou;
  final bool owedIncluded;

  /// Planned money for investments, savings and other categories: not
  /// spendable, so not part of the number.
  final int setAside;

  /// Balance of the account(s) your spending budget draws from, or null if
  /// the budget is not linked to an account.
  final int? spendingAccountBalance;
  final int daysToPayday;
  final SafeToSpendResult result;

  int get budgetLeft => planned + carriedOver - spent;

  /// Spent more than planned.
  bool get overBudget => budgetLeft < 0;

  /// The budget promises more than the linked account actually holds.
  bool get budgetExceedsAccount =>
      spendingAccountBalance != null &&
      spendingAccountBalance! >= 0 &&
      budgetLeft > spendingAccountBalance!;
}
