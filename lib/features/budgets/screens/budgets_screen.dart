import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/financial_amount_text.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/role_badge.dart';
import 'package:rivero/features/budgets/widgets/create_budget_sheet.dart';
import 'package:rivero/features/plan/salary_plan_screen.dart';

/// Screen managing monthly salary waterfall allocations and purpose-driven spending budgets.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucketsAsync = ref.watch(allAllocationBucketsProvider);
    final accountsAsync = ref.watch(activePhysicalAccountsProvider);
    final isPrivacy = ref.watch(privacyModeProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Budgets & Allocations',
        subtitle: 'Purpose-Driven Monthly Waterfall',
        actions: [
          IconButton(
            tooltip: 'Salary Plan',
            icon: const Icon(Icons.call_split_rounded),
            onPressed: () => SalaryPlanScreen.open(context),
          ),
          IconButton(
            tooltip: 'Add Purpose Bucket',
            icon: const Icon(
              Icons.add_chart_rounded,
              color: RiveroColors.salaryAccent,
            ),
            onPressed: () => CreateBudgetSheet.show(context),
          ),
        ],
      ),
      body: bucketsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              RiveroColors.salaryAccent,
            ),
          ),
        ),
        error: (err, _) => Center(
          child: Text(
            'Failed to load budget allocations: $err',
            style: RiveroTypography.bodyMedium.copyWith(
              color: RiveroColors.danger,
            ),
          ),
        ),
        data: (buckets) {
          final accounts = accountsAsync.value ?? [];

          // Compute total salary received from salary accounts
          final salaryMinorUnits = ref.watch(monthlySalaryProvider);

          var totalAllocatedMinorUnits = 0;
          var totalSpentMinorUnits = 0;
          for (final b in buckets) {
            totalAllocatedMinorUnits += b.allocatedMinorUnits;
            totalSpentMinorUnits += b.spentMinorUnits;
          }

          final unallocatedRemainingMinorUnits =
              salaryMinorUnits - totalAllocatedMinorUnits;

          return RefreshIndicator(
            color: RiveroColors.salaryAccent,
            backgroundColor: RiveroColors.surfaceElevated,
            onRefresh: () async {
              ref.invalidate(allAllocationBucketsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: RiveroSpacing.lg,
                vertical: RiveroSpacing.md,
              ),
              children: [
                // 1. Waterfall Allocation Meter (Conservation of Value)
                RiveroCard(
                  isElevated: true,
                  borderColor: RiveroColors.salaryAccent.withValues(alpha: 0.3),
                  padding: const EdgeInsets.all(RiveroSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'MONTHLY SALARY POOL',
                              style: RiveroTypography.labelSmall.copyWith(
                                letterSpacing: 1.2,
                                color: RiveroColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: RiveroSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: RiveroColors.salaryAccent.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(
                                RiveroRadii.full,
                              ),
                            ),
                            child: Text(
                              'Waterfall Invariant',
                              style: RiveroTypography.labelSmall.copyWith(
                                color: RiveroColors.salaryAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: RiveroSpacing.xs),
                      if (isPrivacy)
                        Text('••••••••', style: RiveroTypography.financialHero)
                      else
                        FinancialAmountText(
                          minorUnits: salaryMinorUnits,
                          size: FinancialAmountSize.hero,
                        ),
                      const SizedBox(height: RiveroSpacing.md),

                      // Breakdown row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: _MetricColumn(
                              label: 'Allocated to Purposes',
                              amountMinorUnits: totalAllocatedMinorUnits,
                              color: RiveroColors.salaryAccent,
                              isPrivacy: isPrivacy,
                            ),
                          ),
                          const SizedBox(width: RiveroSpacing.sm),
                          Expanded(
                            child: _MetricColumn(
                              label: 'Unallocated Remaining',
                              amountMinorUnits: unallocatedRemainingMinorUnits,
                              color: unallocatedRemainingMinorUnits >= 0
                                  ? RiveroColors.savingsAccent
                                  : RiveroColors.danger,
                              isPrivacy: isPrivacy,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: RiveroSpacing.md),

                      // Waterfall progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(RiveroRadii.full),
                        child: LinearProgressIndicator(
                          value: salaryMinorUnits > 0
                              ? (totalAllocatedMinorUnits / salaryMinorUnits)
                                    .clamp(0.0, 1.0)
                              : 0.0,
                          minHeight: 6,
                          backgroundColor: RiveroColors.surfaceInteractive,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            RiveroColors.salaryAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: RiveroSpacing.xs),
                      Text(
                        'Total Spent so far: ${CurrencyFormatter.format(totalSpentMinorUnits)}',
                        style: RiveroTypography.bodySmall.copyWith(
                          fontSize: 11,
                          color: RiveroColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: RiveroSpacing.xl),

                // 2. Purpose Buckets List
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'MONTHLY ALLOCATION PURPOSES',
                        style: RiveroTypography.labelSmall.copyWith(
                          letterSpacing: 1.2,
                          color: RiveroColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: RiveroSpacing.sm),
                    Text(
                      '${buckets.length} Active',
                      style: RiveroTypography.labelSmall.copyWith(
                        color: RiveroColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.sm),

                if (buckets.isEmpty)
                  RiveroCard(
                    padding: const EdgeInsets.all(RiveroSpacing.xl),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.pie_chart_outline_rounded,
                            color: RiveroColors.textMuted,
                            size: 32,
                          ),
                          const SizedBox(height: RiveroSpacing.xs),
                          Text(
                            'No Budget Purposes Defined',
                            style: RiveroTypography.titleMedium,
                          ),
                          const SizedBox(height: RiveroSpacing.xs),
                          Text(
                            'Create your monthly purpose buckets to allocate salary automatically.',
                            style: RiveroTypography.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...buckets.map((bucket) {
                    final remaining =
                        bucket.allocatedMinorUnits - bucket.spentMinorUnits;
                    final progress = bucket.allocatedMinorUnits > 0
                        ? (bucket.spentMinorUnits / bucket.allocatedMinorUnits)
                              .clamp(0.0, 1.0)
                        : 0.0;

                    final linkedAccount = accounts
                        .where((a) => a.id == bucket.linkedPhysicalAccountId)
                        .firstOrNull;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: RiveroSpacing.md),
                      child: RiveroCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      RoleBadge(
                                        role: bucket.role,
                                        isCompact: true,
                                      ),
                                      const SizedBox(width: RiveroSpacing.sm),
                                      Expanded(
                                        child: Text(
                                          bucket.name,
                                          style: RiveroTypography.titleMedium
                                              .copyWith(fontSize: 15),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: RiveroSpacing.sm),
                                if (isPrivacy)
                                  Text(
                                    '••••••••',
                                    style: RiveroTypography.monoMedium,
                                  )
                                else
                                  Text(
                                    '${CurrencyFormatter.format(remaining)} left',
                                    style: RiveroTypography.monoMedium.copyWith(
                                      color: remaining < 0
                                          ? RiveroColors.danger
                                          : RiveroColors.investmentAccent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                              ],
                            ),

                            if (linkedAccount != null) ...[
                              const SizedBox(height: RiveroSpacing.xs),
                              Text(
                                'Deducts from: ${linkedAccount.name} (${linkedAccount.institution} ••${linkedAccount.accountMask})',
                                style: RiveroTypography.bodySmall.copyWith(
                                  fontSize: 11,
                                  color: RiveroColors.textMuted,
                                ),
                              ),
                            ],

                            const SizedBox(height: RiveroSpacing.md),

                            // Spent vs Allocated numbers
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Spent: ${CurrencyFormatter.format(bucket.spentMinorUnits)}',
                                  style: RiveroTypography.bodySmall.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  'Monthly Budget: ${CurrencyFormatter.format(bucket.allocatedMinorUnits)}',
                                  style: RiveroTypography.bodySmall.copyWith(
                                    fontSize: 12,
                                    color: RiveroColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: RiveroSpacing.xs),

                            // Progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                RiveroRadii.full,
                              ),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                backgroundColor:
                                    RiveroColors.surfaceInteractive,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _roleColor(bucket.role),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _roleColor(AccountRole role) {
    switch (role) {
      case AccountRole.salaryRoot:
        return RiveroColors.salaryAccent;
      case AccountRole.expense:
        return RiveroColors.expenseAccent;
      case AccountRole.investment:
        return RiveroColors.investmentAccent;
      case AccountRole.savings:
        return RiveroColors.savingsAccent;
      case AccountRole.custom:
        return RiveroColors.customAccent;
      case AccountRole.liabilityCc:
        return RiveroColors.liabilityAccent;
      case AccountRole.virtualWallet:
        return RiveroColors.walletAccent;
    }
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.label,
    required this.amountMinorUnits,
    required this.color,
    required this.isPrivacy,
  });

  final String label;
  final int amountMinorUnits;
  final Color color;
  final bool isPrivacy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: RiveroTypography.bodySmall.copyWith(fontSize: 11)),
        const SizedBox(height: 2),
        if (isPrivacy)
          Text('••••••••', style: RiveroTypography.titleMedium)
        else
          Text(
            CurrencyFormatter.format(amountMinorUnits),
            style: RiveroTypography.titleMedium.copyWith(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}
