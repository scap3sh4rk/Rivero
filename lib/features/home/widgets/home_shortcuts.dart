import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/card_cycle.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/spending_summary.dart';
import 'package:rivero/core/mandates/autopay_actions.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bento_tile.dart';
import 'package:rivero/features/accounts/screens/account_detail_screen.dart';
import 'package:rivero/features/budgets/screens/budgets_screen.dart';
import 'package:rivero/features/home/home_widgets.dart';
import 'package:rivero/features/home/widgets/goals_home_card.dart';
import 'package:rivero/features/mandates/mandates_screen.dart';

/// The quiet cards under the hero, the ones the user picked (Settings >
/// Home screen), in their order.
class HomeShortcuts extends ConsumerWidget {
  const HomeShortcuts({super.key});

  static const owedTab = 0;
  static const activityTab = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) =>
        privacy ? '••••' : CurrencyFormatter.formatCompact(v);
    final buckets = ref.watch(allAllocationBucketsProvider).value ?? const [];
    final salary = ref.watch(monthlySalaryProvider);
    final setAside = buckets
        .where((b) => b.role != AccountRole.expense)
        .fold<int>(0, (s, b) => s + b.allocatedMinorUnits);
    final dues = ref.watch(duesProvider).value ?? const [];
    final owed = DuesService.totalOutstanding(dues);
    final owedPeople = {
      for (final d in dues)
        if (d.status == DueStatus.open &&
            d.amountMinorUnits > d.receivedMinorUnits &&
            d.kind != DueKind.borrowed)
          d.person.trim().toLowerCase(),
    }.length;
    final mandates = [...?ref.watch(activeMandatesProvider).value]
      ..removeWhere((m) => m.nextExecutionDate == null);
    final next = mandates.isEmpty ? null : mandates.first;
    final cycle = ref.watch(currentPaycycleProvider);
    final spent = SpendingSummary.of(
      ref.watch(allTransactionsStreamProvider).value ?? const [],
      start: cycle.cycleStartDate,
      end: DateTime.now(),
      othersShare: DuesService.othersShareByTransaction(
        ref.watch(duesProvider).value ?? const [],
      ),
      // Everyday spending, like Safe to spend: rent and family paid through
      // the plan are not in it.
      includePlan: false,
      toHome: ref.watch(toHomeProvider),
    ).total;
    void tab(int i) => ref.read(selectedNavIndexProvider.notifier).state = i;

    // Both tiles in a row take the taller one's height: never uneven.
    Widget row(Widget a, Widget b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: RiveroSpacing.md),
          Expanded(child: b),
        ],
      ),
    );

    // Net worth: the accounts kept in it, in rupees.
    final counted = ref
        .watch(exchangeRatesProvider)
        .inHome(ref.watch(activePhysicalAccountsProvider).value ?? const [])
        .where((a) => a.includeInNetWorth);
    final netWorth = counted.fold<int>(
      0,
      (s, a) => a.isLiability
          ? s + (a.balanceMinorUnits < 0 ? a.balanceMinorUnits : 0)
          : s + a.balanceMinorUnits,
    );
    // Card bills: everything cards owe, and the soonest due date.
    final cards = (ref.watch(activePhysicalAccountsProvider).value ?? const [])
        .where(
          (a) =>
              a.isLiability &&
              !StandardAccountTypes.isLongTermDebt(a.accountType) &&
              a.balanceMinorUnits < 0,
        )
        .toList();
    // What the cards' last statements ask for (spends since go on the next).
    final cardBills = ref.watch(cardBillsProvider);
    final cardOwed = cards.fold<int>(
      0,
      (s, c) => s + (cardBills[c.id]?.due ?? -c.balanceMinorUnits),
    );
    final dueDates = [
      for (final c in cards)
        if ((cardBills[c.id]?.due ?? 1) > 0)
          ?CardCycle.of(
            statementDay: c.statementDay,
            paymentDueDay: c.paymentDueDay,
            now: DateTime.now(),
          )?.dueDate,
    ]..sort();
    final youOwe = DuesService.totalYouOwe(dues);
    final youOwePeople = {
      for (final d in dues)
        if (d.status == DueStatus.open &&
            d.kind == DueKind.borrowed &&
            d.amountMinorUnits > d.receivedMinorUnits)
          d.person.trim().toLowerCase(),
    }.length;

    Widget tile(HomeWidget w) => switch (w) {
      HomeWidget.plan => BentoTile(
        key: const ValueKey('home-plan'),
        label: 'PLAN',
        value: salary == 0
            ? 'Set up'
            : money((salary - setAside).clamp(0, salary)),
        caption: salary == 0 ? 'Your salary plan' : 'to spend a month',
        onTap: () => BudgetsScreen.open(context),
      ),
      HomeWidget.owed => BentoTile(
        key: const ValueKey('home-owed'),
        label: 'OWED TO YOU',
        value: money(owed),
        caption: owedPeople == 0
            ? 'Nobody'
            : '$owedPeople ${owedPeople == 1 ? 'person' : 'people'}',
        onTap: () => tab(owedTab),
      ),
      HomeWidget.autopay => BentoTile(
        key: const ValueKey('home-autopay'),
        label: 'NEXT AUTOPAY',
        leading: next == null
            ? null
            : MandateKindIcon(AutopayActions.kindOf(next), size: 18),
        value: next == null ? 'None' : next.payee,
        caption: next == null
            ? 'Nothing due'
            : isOverdue(next, DateTime.now())
            ? 'Overdue since '
                  '${DateFormat('d MMM').format(next.nextExecutionDate!)}'
            : '${money(mandateReserve(next))} · '
                  '${DateFormat('d MMM').format(next.nextExecutionDate!)}',
        onTap: () => MandatesScreen.open(context),
      ),
      HomeWidget.spent => BentoTile(
        key: const ValueKey('home-spent'),
        label: 'SPENT THIS CYCLE',
        value: money(spent),
        caption: '${cycle.daysRemaining} days to payday',
        onTap: () => tab(activityTab),
      ),
      HomeWidget.netWorth => BentoTile(
        key: const ValueKey('home-networth'),
        label: 'NET WORTH',
        value: money(netWorth),
        caption: '${counted.length} accounts',
        onTap: () => NetWorthSheet.show(context),
      ),
      HomeWidget.cardBills => BentoTile(
        key: const ValueKey('home-cardbills'),
        label: 'CARD BILLS',
        value: money(cardOwed),
        caption: cardOwed == 0
            ? 'Nothing to settle'
            : dueDates.isEmpty
            ? '${cards.length} cards'
            : 'Next due ${DateFormat('d MMM').format(dueDates.first)}',
        onTap: () => tab(owedTab),
      ),
      HomeWidget.youOwe => BentoTile(
        key: const ValueKey('home-youowe'),
        label: 'YOU OWE',
        value: money(youOwe),
        caption: youOwePeople == 0
            ? 'Nobody'
            : '$youOwePeople ${youOwePeople == 1 ? 'person' : 'people'}',
        onTap: () => tab(owedTab),
      ),
      HomeWidget.goals => const GoalsHomeCard(),
    };

    // The chosen widgets in the chosen order: small tiles two to a row
    // (a lone one keeps the same width), Goals across the full width.
    final chosen = HomeWidget.chosen(ref.watch(homeWidgetsProvider));
    final children = <Widget>[];
    final pending = <Widget>[];
    void flush() {
      if (pending.isEmpty) return;
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: RiveroSpacing.md));
      }
      children.add(
        row(pending[0], pending.length > 1 ? pending[1] : const SizedBox()),
      );
      pending.clear();
    }

    for (final w in chosen) {
      if (w.wide) {
        flush();
        children.add(tile(w));
      } else {
        pending.add(tile(w));
        if (pending.length == 2) flush();
      }
    }
    flush();
    return Column(children: children);
  }
}
