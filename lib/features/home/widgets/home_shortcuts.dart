import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/spending_summary.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bento_tile.dart';
import 'package:rivero/features/budgets/screens/budgets_screen.dart';
import 'package:rivero/features/mandates/mandates_screen.dart';

/// Four quiet shortcuts under the hero: plan, owed, next autopay, spent.
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
    final owed = DuesService.totalOutstanding(
      ref.watch(duesProvider).value ?? const [],
    );
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
    ).total;
    void tab(int i) => ref.read(selectedNavIndexProvider.notifier).state = i;

    Widget row(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: RiveroSpacing.md),
        Expanded(child: b),
      ],
    );

    return Column(
      children: [
        row(
          BentoTile(
            key: const ValueKey('home-plan'),
            label: 'PLAN',
            value: salary == 0
                ? 'Set up'
                : '${money((salary - setAside).clamp(0, salary))} / month',
            onTap: () => BudgetsScreen.open(context),
          ),
          BentoTile(
            key: const ValueKey('home-owed'),
            label: 'OWED TO YOU',
            value: money(owed),
            onTap: () => tab(owedTab),
          ),
        ),
        const SizedBox(height: RiveroSpacing.md),
        row(
          BentoTile(
            key: const ValueKey('home-autopay'),
            label: 'NEXT AUTOPAY',
            value: next == null
                ? 'None'
                : '${next.payee} · '
                      '${DateFormat('d MMM').format(next.nextExecutionDate!)}',
            onTap: () => MandatesScreen.open(context),
          ),
          BentoTile(
            key: const ValueKey('home-spent'),
            label: 'SPENT THIS CYCLE',
            value: money(spent),
            onTap: () => tab(activityTab),
          ),
        ),
      ],
    );
  }
}
