import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/financial_amount_text.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/role_badge.dart';

/// Widget displaying physical custodial bank accounts and virtual waterfall budget buckets.
class AccountsAndBucketsList extends ConsumerWidget {
  const AccountsAndBucketsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(activePhysicalAccountsProvider);
    final bucketsAsync = ref.watch(allAllocationBucketsProvider);
    final isPrivacy = ref.watch(privacyModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ACCOUNTS & ALLOCATIONS',
              style: RiveroTypography.labelSmall.copyWith(
                letterSpacing: 1.5,
                color: RiveroColors.textMuted,
              ),
            ),
            Text(
              'Two-Tier Ledger',
              style: RiveroTypography.bodySmall.copyWith(
                color: RiveroColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: RiveroSpacing.md),

        // 1. Custodial Physical Accounts Horizontal Carousel
        accountsAsync.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Text(
            'Error: $err',
            style: RiveroTypography.bodySmall.copyWith(
              color: RiveroColors.danger,
            ),
          ),
          data: (accounts) {
            if (accounts.isEmpty) return const SizedBox.shrink();

            return SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: accounts.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: RiveroSpacing.md),
                itemBuilder: (context, index) {
                  final acc = accounts[index];
                  final isLiability = acc.isLiability;
                  final border = isLiability
                      ? RiveroColors.liabilityAccent.withValues(alpha: 0.3)
                      : RiveroColors.borderMedium;

                  return SizedBox(
                    width: 220,
                    child: RiveroCard(
                      borderColor: border,
                      padding: const EdgeInsets.all(RiveroSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  acc.institution,
                                  style: RiveroTypography.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: RiveroColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '••${acc.accountMask}',
                                style: RiveroTypography.monoSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: RiveroSpacing.xs),
                          Text(
                            acc.name,
                            style: RiveroTypography.titleMedium.copyWith(
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          if (isPrivacy)
                            Text(
                              '••••••••',
                              style: RiveroTypography.financialMedium.copyWith(
                                fontSize: 16,
                              ),
                            )
                          else
                            FinancialAmountText(
                              minorUnits: acc.balanceMinorUnits,
                              customColor:
                                  isLiability && acc.balanceMinorUnits < 0
                                  ? RiveroColors.liabilityAccent
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),

        const SizedBox(height: RiveroSpacing.lg),

        // 2. Virtual Allocation Buckets List
        bucketsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (buckets) {
            if (buckets.isEmpty) return const SizedBox.shrink();

            return Column(
              children: buckets.map((bucket) {
                final remaining =
                    bucket.allocatedMinorUnits - bucket.spentMinorUnits;
                final progress = bucket.allocatedMinorUnits > 0
                    ? (bucket.spentMinorUnits / bucket.allocatedMinorUnits)
                          .clamp(0, 1)
                          .toDouble()
                    : 0.0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
                  child: RiveroCard(
                    padding: const EdgeInsets.all(RiveroSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  RoleBadge(role: bucket.role, isCompact: true),
                                  const SizedBox(width: RiveroSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      bucket.name,
                                      style: RiveroTypography.bodyLarge
                                          .copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
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
                                style: RiveroTypography.bodyMedium,
                              )
                            else
                              Text(
                                '${CurrencyFormatter.format(remaining)} left',
                                style: RiveroTypography.monoMedium.copyWith(
                                  color: remaining < 0
                                      ? RiveroColors.danger
                                      : RiveroColors.textPrimary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: RiveroSpacing.sm),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(RiveroRadii.full),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: RiveroColors.surfaceInteractive,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _roleColor(bucket.role),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
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
