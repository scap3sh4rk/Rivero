import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/financial_amount_text.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/role_badge.dart';

/// The central Safe-to-Spend Hero Card displaying real-time liquidity,
/// daily spending pace, paycycle progress, and data reliability badges.
class SafeToSpendHeroCard extends ConsumerWidget {
  const SafeToSpendHeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stsAsync = ref.watch(liveSafeToSpendResultProvider);
    final isPrivacy = ref.watch(privacyModeProvider);
    final paycycle = ref.watch(currentPaycycleProvider);

    final stsResult =
        stsAsync.value ??
        const SafeToSpendResult(
          expenseBalance: 4825000,
          upcomingMandates: 119800,
          unsettledCreditCardLiability: 1425000,
          pendingReimbursements: 0,
          effectiveSafeToSpend: 3280200,
          nominalSafeToSpend: 3280200,
          conservativeSafeToSpend: 3280200,
          dailySpendingPace: 182233,
          isDeficit: false,
          deficitAmount: 0,
          reliability: BalanceReliability.verified,
          daysRemainingInCycle: 18,
        );

    final isDeficit = stsResult.isDeficit;
    final cardBorder = isDeficit
        ? RiveroColors.expenseAccent.withValues(alpha: 0.5)
        : RiveroColors.borderHighlight;

    return RiveroCard(
      isElevated: true,
      borderColor: cardBorder,
      padding: const EdgeInsets.all(RiveroSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: label, reliability badge, role
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'SAFE TO SPEND',
                    style: RiveroTypography.labelSmall.copyWith(
                      letterSpacing: 1.5,
                      color: RiveroColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: RiveroSpacing.sm),
                  _ReliabilityBadge(reliability: stsResult.reliability),
                ],
              ),
              const RoleBadge(role: AccountRole.expense, isCompact: true),
            ],
          ),
          const SizedBox(height: RiveroSpacing.sm),

          // Primary amount hero display
          if (isPrivacy)
            Text(
              '••••••••',
              style: RiveroTypography.financialHero.copyWith(
                color: RiveroColors.textPrimary,
              ),
            )
          else
            FinancialAmountText(
              minorUnits: stsResult.effectiveSafeToSpend,
              size: FinancialAmountSize.hero,
              isAnimated: true,
              customColor: isDeficit ? RiveroColors.expenseAccent : null,
            ),

          const SizedBox(height: RiveroSpacing.xs),

          // Daily Pace subtitle
          if (isDeficit)
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: RiveroColors.expenseAccent,
                ),
                const SizedBox(width: RiveroSpacing.xs),
                Expanded(
                  child: Text(
                    'Deficit: Commitments exceed balance by '
                    '${CurrencyFormatter.format(stsResult.deficitAmount)}',
                    style: RiveroTypography.bodySmall.copyWith(
                      color: RiveroColors.expenseAccent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(
                  Icons.speed,
                  size: 14,
                  color: RiveroColors.savingsAccent,
                ),
                const SizedBox(width: RiveroSpacing.xs),
                Expanded(
                  child: Text(
                    'Pace: ${CurrencyFormatter.format(stsResult.dailySpendingPace)} / day · '
                    '${paycycle.daysRemaining} days left in cycle',
                    style: RiveroTypography.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

          const SizedBox(height: RiveroSpacing.md),

          // Paycycle linear progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(RiveroRadii.full),
            child: LinearProgressIndicator(
              value: paycycle.progress,
              minHeight: 4,
              backgroundColor: RiveroColors.surfaceInteractive,
              valueColor: const AlwaysStoppedAnimation<Color>(
                RiveroColors.salaryAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReliabilityBadge extends StatelessWidget {
  const _ReliabilityBadge({required this.reliability});

  final BalanceReliability reliability;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;

    switch (reliability) {
      case BalanceReliability.verified:
        color = RiveroColors.savingsAccent;
        label = 'Verified';
      case BalanceReliability.estimated:
        color = RiveroColors.salaryAccent;
        label = 'Estimated';
      case BalanceReliability.stale:
        color = RiveroColors.expenseAccent;
        label = 'Stale';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(RiveroRadii.full),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: RiveroTypography.labelSmall.copyWith(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
