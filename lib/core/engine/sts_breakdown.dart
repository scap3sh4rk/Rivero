import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/plan/plan_transfer_service.dart';

/// Everything behind the Safe-to-Spend number, in the order it is used.
/// The Home card and the "how is this calculated" sheet both read this, so
/// they can never disagree.
///
///   budget left = planned + carried over − spent
///   usable = what the spending account really holds (minus money in it the
///            plan promised elsewhere). The account is the truth; the budget
///            is only used when no spending account is linked.
///   safe to spend = usable − autopay due − card bills (+ owed to you)
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
    required this.reservedInAccount,
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
    String? salaryAccountId,
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

    // Autopay taken from another bank account (a SIP from the salary
    // account) does not touch spending money; from the spending account or
    // a card it does.
    final otherBanks = {
      for (final a in accounts)
        if (!a.isLiability && !linked.contains(a.id)) a.id,
    };
    final due = upcomingMandates(mandates, at, cycle.cycleEndDate)
        .where(
          (m) =>
              accountBalance == null ||
              !otherBanks.contains(m.physicalAccountId),
        )
        .toList();
    final dueTotal = due.fold<int>(0, (s, m) => s + mandateReserve(m));

    // Money in the spending account that the plan has promised elsewhere
    // (e.g. rent that is paid out of the same account), not spendable.
    // Plan-only categories are paid out of the SALARY account, so they only
    // tie up money when that account is the one spending draws from.
    final salaryId = PlanTransferService.salaryAccountOf(
      accounts,
      salaryAccountId,
    )?.id;
    final reserved = accountBalance == null || !linked.contains(salaryId)
        ? 0
        : buckets
              .where(
                (b) =>
                    b.role != AccountRole.expense &&
                    (b.linkedPhysicalAccountId == null ||
                        linked.contains(b.linkedPhysicalAccountId)),
              )
              .fold<int>(
                0,
                (s, b) =>
                    s +
                    (b.allocatedMinorUnits - b.spentMinorUnits).clamp(
                      0,
                      b.allocatedMinorUnits,
                    ),
              );
    final budgetLeft = planned + carried - spent;
    final inAccount = accountBalance == null ? null : accountBalance - reserved;
    final usable = inAccount ?? budgetLeft;

    final result = calculator.calculate(
      expenseBalance: usable,
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
      reservedInAccount: reserved,
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

  /// Part of that balance promised to plan-only categories.
  final int reservedInAccount;
  final int daysToPayday;
  final SafeToSpendResult result;

  int get budgetLeft => planned + carriedOver - spent;

  /// Planned + carried over: the "of" in "₹X left of ₹Y".
  int get planTotal => planned + carriedOver;

  /// Less than nothing left to spend (account overdrawn, or overspent).
  bool get overBudget => usable < 0;

  /// What the account really holds for spending (balance minus money the
  /// plan has promised elsewhere), or null when no account is linked.
  int? get accountAvailable => spendingAccountBalance == null
      ? null
      : spendingAccountBalance! - reservedInAccount;

  /// Safe to spend follows the linked spending account's real balance.
  bool get fromAccount => accountAvailable != null;

  /// What is left to spend: the account's free money, or (no account
  /// linked) the budget left. Every screen shows this one number.
  int get usable => accountAvailable ?? budgetLeft;
}
