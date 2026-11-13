import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/credit_utilization.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Card visualizing credit line utilization with 10% safe and 30% credit score impact indicators.
class CreditUtilizationCard extends ConsumerWidget {
  const CreditUtilizationCard({required this.account, super.key});

  final PhysicalAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPrivacy = ref.watch(privacyModeProvider);
    final utilization = CreditUtilization.fromBalance(
      creditLimitMinorUnits: account.creditLimitMinorUnits,
      balanceMinorUnits: account.balanceMinorUnits,
    );

    final statusColor = utilization.statusColor;

    return RiveroCard(
      borderColor: statusColor.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Account name, mask, and status badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(RiveroSpacing.xs),
                      decoration: BoxDecoration(
                        color: RiveroColors.surfaceInteractive,
                        borderRadius: BorderRadius.circular(RiveroRadii.xs),
                      ),
                      child: const Icon(
                        Icons.credit_score_rounded,
                        size: 16,
                        color: RiveroColors.liabilityAccent,
                      ),
                    ),
                    const SizedBox(width: RiveroSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.name,
                            style: RiveroTypography.titleMedium.copyWith(
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${account.institution} · ••${account.accountMask}',
                            style: RiveroTypography.bodySmall.copyWith(
                              fontSize: 11,
                              color: RiveroColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RiveroSpacing.sm),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(RiveroRadii.full),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  utilization.badgeLabel,
                  style: RiveroTypography.labelSmall.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: RiveroSpacing.md),

          // Numbers Row: Spent vs Limit
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT USAGE (${utilization.utilizationPercent.toStringAsFixed(1)}%)',
                    style: RiveroTypography.labelSmall.copyWith(
                      fontSize: 10,
                      letterSpacing: 1.1,
                      color: RiveroColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (isPrivacy)
                    Text('••••••••', style: RiveroTypography.financialLarge)
                  else
                    Text(
                      CurrencyFormatter.format(utilization.usedMinorUnits),
                      style: RiveroTypography.financialLarge.copyWith(
                        color: statusColor,
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'CREDIT LIMIT',
                    style: RiveroTypography.labelSmall.copyWith(
                      fontSize: 10,
                      letterSpacing: 1.1,
                      color: RiveroColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (isPrivacy)
                    Text('••••••••', style: RiveroTypography.titleMedium)
                  else
                    Text(
                      CurrencyFormatter.format(
                        utilization.creditLimitMinorUnits,
                      ),
                      style: RiveroTypography.titleMedium.copyWith(
                        color: RiveroColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: RiveroSpacing.md),

          // Multi-tier Gauge / Progress Bar
          // Scale: 0% to 100%
          ClipRRect(
            borderRadius: BorderRadius.circular(RiveroRadii.full),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  // Background
                  Container(color: RiveroColors.surfaceInteractive),

                  // Progress Fill
                  FractionallySizedBox(
                    widthFactor: (utilization.utilizationPercent / 100.0).clamp(
                      0.0,
                      1.0,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(RiveroRadii.full),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: RiveroSpacing.xs),

          // Indicator Markers: 10% Safe, 30% Threshold
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0%',
                style: RiveroTypography.labelSmall.copyWith(
                  fontSize: 9,
                  color: RiveroColors.textMuted,
                ),
              ),
              Text(
                '10% (Safe)',
                style: RiveroTypography.labelSmall.copyWith(
                  fontSize: 9,
                  color: RiveroColors.investmentAccent,
                ),
              ),
              Text(
                '30% (Score Alert)',
                style: RiveroTypography.labelSmall.copyWith(
                  fontSize: 9,
                  color: RiveroColors.salaryAccent,
                ),
              ),
              Text(
                '100%',
                style: RiveroTypography.labelSmall.copyWith(
                  fontSize: 9,
                  color: RiveroColors.textMuted,
                ),
              ),
            ],
          ),

          const SizedBox(height: RiveroSpacing.sm),

          // Advice Text
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RiveroSpacing.sm,
              vertical: RiveroSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(RiveroRadii.xs),
            ),
            child: Row(
              children: [
                Icon(
                  utilization.tier == CreditUtilizationTier.safe
                      ? Icons.check_circle_outline_rounded
                      : (utilization.tier == CreditUtilizationTier.moderate
                            ? Icons.info_outline_rounded
                            : Icons.warning_amber_rounded),
                  size: 13,
                  color: statusColor,
                ),
                const SizedBox(width: RiveroSpacing.xs),
                Expanded(
                  child: Text(
                    utilization.adviceMessage,
                    style: RiveroTypography.bodySmall.copyWith(
                      fontSize: 10,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
