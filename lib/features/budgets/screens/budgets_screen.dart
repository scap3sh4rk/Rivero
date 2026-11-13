import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bento_tile.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/mandates/mandates_screen.dart';
import 'package:rivero/features/owed/owed_screen.dart';
import 'package:rivero/features/plan/salary_plan_screen.dart';

/// Plan: where this month's salary goes. One card for the salary, one short
/// row per category. Editing happens on the Salary plan page.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = ref.watch(allAllocationBucketsProvider).value ?? const [];
    final salary = ref.watch(monthlySalaryProvider);
    final privacy = ref.watch(privacyModeProvider);
    final mandates = ref.watch(activeMandatesProvider).value?.length ?? 0;

    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);

    final ordered = [...buckets]
      ..sort((a, b) {
        // Spending first, then the set-aside categories in plan order.
        int rank(AllocationBucket x) => x.role == AccountRole.expense ? 0 : 1;
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.priorityOrder.compareTo(b.priorityOrder);
      });
    final setAside = buckets
        .where((b) => b.role != AccountRole.expense)
        .fold<int>(0, (s, b) => s + b.allocatedMinorUnits);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: const RiveroAppBar(title: 'Plan'),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: BentoTile(
                  label: 'AUTOPAY',
                  value: '$mandates Active',
                  onTap: () => MandatesScreen.open(context),
                ),
              ),
              const SizedBox(width: RiveroSpacing.md),
              Expanded(
                child: BentoTile(
                  key: const ValueKey('owed-tile'),
                  label: 'OWED TO YOU',
                  value: money(
                    DuesService.totalOutstanding(
                      ref.watch(duesProvider).value ?? const [],
                    ),
                  ),
                  onTap: () => OwedScreen.open(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: RiveroSpacing.md),
          RiveroCard(
            isElevated: true,
            onTap: () => SalaryPlanScreen.open(context),
            padding: const EdgeInsets.all(RiveroSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'MONTHLY SALARY',
                        style: RiveroTypography.labelSmall.copyWith(
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    Text(
                      salary == 0 ? 'Set up' : 'Edit plan',
                      style: RiveroTypography.labelLarge,
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: RiveroColors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.sm),
                Text(
                  salary == 0 ? 'Not set' : money(salary),
                  style: RiveroTypography.financialLarge,
                ),
                if (salary > 0) ...[
                  const SizedBox(height: RiveroSpacing.xs),
                  Text(
                    '${money(setAside)} set aside · '
                    '${money((salary - setAside).clamp(0, salary))} for spending',
                    style: RiveroTypography.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: RiveroSpacing.xl),
          Text('Categories', style: RiveroTypography.titleMedium),
          const SizedBox(height: RiveroSpacing.sm),
          if (ordered.isEmpty)
            Text(
              'Set up your salary plan to create categories.',
              style: RiveroTypography.bodySmall,
            ),
          for (final b in ordered)
            _CategoryTile(b, money: money)
                .animate()
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.05, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile(this.b, {required this.money});

  final AllocationBucket b;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) {
    final spending = b.role == AccountRole.expense;
    final total = b.allocatedMinorUnits + b.carryOverMinorUnits;
    final left = total - b.spentMinorUnits;
    // Spending shows what is left; set-aside categories show what is reserved
    // (and how much of it has been paid, for things like rent).
    final detail = spending
        ? '${money(left)} left of ${money(total)}'
        : b.spentMinorUnits > 0
        ? '${money(b.spentMinorUnits)} paid of ${money(total)}'
        : '${money(total)} set aside';
    final used = total > 0 ? (b.spentMinorUnits / total).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
      child: RiveroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.name, style: RiveroTypography.bodyLarge),
            const SizedBox(height: RiveroSpacing.xs),
            Text(
              detail,
              style: RiveroTypography.bodySmall.copyWith(
                color: spending && left < 0 ? RiveroColors.danger : null,
              ),
            ),
            if (spending || b.spentMinorUnits > 0) ...[
              const SizedBox(height: RiveroSpacing.sm),
              ClipRRect(
                borderRadius: RiveroRadii.borderFull,
                child: LinearProgressIndicator(
                  value: used,
                  minHeight: 4,
                  backgroundColor: RiveroColors.surfaceInteractive,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    RiveroColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
