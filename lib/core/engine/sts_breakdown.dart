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
    required this.cardBillsTotal,
    required this.owedToYou,
    required this.debtsDue,
    required this.owedIncluded,
    required this.setAside,
    required this.spendingAccountBalance,
    required this.reservedInAccount,
    required this.daysToPayday,
    required this.result,
    required this.cycleEnd,
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

    final owed = DuesService.totalOutstanding(dues);
    // Money you promised to pay back before payday is already spoken for.
    final debtsDue = DuesService.youOweDueBy(dues, cycle.cycleEndDate);

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

    // Card bills. A card can be paid from its own account (the user moves
    // each card spend there, e.g. a Slice savings account): what that
    // account already holds is set aside, so only the rest comes out of
    // spending money. Cards paid from the same account share its balance.
    final owing = reserveCards
        ? accounts.where((a) => a.isLiability && a.balanceMinorUnits < 0)
        : const <PhysicalAccount>[];
    final cardsTotal = owing.fold<int>(0, (s, a) => s - a.balanceMinorUnits);
    final byPayer = <String, int>{};
    for (final c in owing) {
      final payer = accounts
          .where(
            (a) =>
                a.id == c.billsPaidFromAccountId &&
                !a.isLiability &&
                !linked.contains(a.id), // paid from spending: nothing apart
          )
          .firstOrNull;
      if (payer != null) {
        byPayer[payer.id] = (byPayer[payer.id] ?? 0) - c.balanceMinorUnits;
      }
    }
    var cardsCovered = 0;
    byPayer.forEach((id, owed) {
      final held = accounts.firstWhere((a) => a.id == id).balanceMinorUnits;
      cardsCovered += owed < held ? owed : (held > 0 ? held : 0);
    });
    final cards = cardsTotal - cardsCovered;

    // Autopay taken from another bank account (a SIP from the salary
    // account) does not touch spending money; from the spending account or
    // a card it does.
    final otherBanks = {
      for (final a in accounts)
        if (!a.isLiability && !linked.contains(a.id)) a.id,
    };
    final due = upcomingMandates(mandates, at, cycle.cycleEndDate)
        // An autopay on a removed account cannot debit anything.
        .where((m) => accounts.any((a) => a.id == m.physicalAccountId))
        .where(
          (m) =>
              accountBalance == null ||
              !otherBanks.contains(m.physicalAccountId),
        )
        .toList();
    final dueTotal = due.fold<int>(
      0,
      (s, m) => s + reserveUntil(m, cycle.cycleEndDate),
    );

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
      upcomingMandates: dueTotal + debtsDue,
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
      cardBillsTotal: cardsTotal,
      owedToYou: owed,
      debtsDue: debtsDue,
      owedIncluded: includeOwed,
      setAside: setAside,
      spendingAccountBalance: accountBalance,
      reservedInAccount: reserved,
      daysToPayday: result.daysRemainingInCycle,
      result: result,
      cycleEnd: cycle.cycleEndDate,
    );
  }

  /// Planned for spending this cycle (salary minus what is set aside).
  final int planned;
  final int carriedOver;
  final int spent;

  /// Autopays still due before payday, soonest first.
  final List<Mandate> mandates;
  final int mandatesTotal;

  /// Unpaid card spend taken from spending money (0 when the card toggle
  /// is off): the total minus what the cards' own accounts already hold.
  final int cardBills;

  /// Everything owed on cards (before money set aside for them).
  final int cardBillsTotal;

  /// Card bills already covered by money kept in the cards' own accounts.
  int get cardBillsSetAside => cardBillsTotal - cardBills;
  final int owedToYou;

  /// Money you borrowed that you promised to repay before payday.
  final int debtsDue;
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

  /// Last moment of this pay cycle.
  final DateTime cycleEnd;
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
