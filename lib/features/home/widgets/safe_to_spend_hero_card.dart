import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/financial_amount_text.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/home/widgets/sts_breakdown_sheet.dart';

/// The single hero of the app: one large Safe-to-Spend number with a pill
/// showing how much of the expense budget is left. The pill shifts from
/// green to amber to red as funds run down.
class SafeToSpendHeroCard extends ConsumerWidget {
  const SafeToSpendHeroCard({super.key});

  /// Pill colour for the fraction of the month's budget remaining. Calm and
  /// neutral while things are fine; it only warms up when money is running
  /// low, and turns red only for a real shortfall.
  static Color toneFor(double remaining, {bool deficit = false}) {
    if (deficit) return RiveroColors.danger;
    final r = remaining.clamp(0.0, 1.0);
    if (r >= 0.35) return RiveroColors.textSecondary;
    if (r >= 0.15) {
      return Color.lerp(
        RiveroColors.warning,
        RiveroColors.textSecondary,
        (r - 0.15) / 0.2,
      )!;
    }
    return Color.lerp(RiveroColors.danger, RiveroColors.warning, r / 0.15)!;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stsAsync = ref.watch(liveSafeToSpendResultProvider);
    final breakdown = ref.watch(stsBreakdownProvider).value;
    final isPrivacy = ref.watch(privacyModeProvider);
    final paycycle = ref.watch(currentPaycycleProvider);
    final awaiting = ref.watch(awaitingSalaryProvider).value ?? false;

    final sts = stsAsync.value;
    if (sts == null) return const SizedBox(height: 220);

    // Same "left" and "of" as the Plan screen and the breakdown sheet.
    final limit = breakdown?.planTotal ?? 0;
    final left = breakdown?.usable ?? 0;
    final remaining = limit > 0 ? left / limit : (sts.isDeficit ? 0.0 : 1.0);
    final tone = toneFor(remaining, deficit: sts.isDeficit);

    // Everything about today's number lives in one card: the figure, what is
    // left, and a thin bar of how much of the month's spending is used.
    return RiveroCard(
      key: const ValueKey('sts-card'),
      isElevated: true,
      onTap: () => StsBreakdownSheet.show(context),
      padding: const EdgeInsets.fromLTRB(
        RiveroSpacing.xl,
        RiveroSpacing.xl,
        RiveroSpacing.xl,
        RiveroSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SAFE TO SPEND PER DAY',
                  style: RiveroTypography.labelSmall.copyWith(
                    letterSpacing: 1.6,
                    color: RiveroColors.textMuted,
                  ),
                ),
              ),
              _ReliabilityDot(reliability: sts.reliability),
              const SizedBox(width: RiveroSpacing.xs),
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: RiveroColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: RiveroSpacing.sm),
          if (isPrivacy)
            Text(
              '••••••••',
              style: RiveroTypography.financialHero.copyWith(
                fontWeight: FontWeight.w800,
              ),
            )
          else
            FinancialAmountText(
              minorUnits: sts.isDeficit ? 0 : sts.dailySpendingPace,
              size: FinancialAmountSize.hero,
              isAnimated: true,
              includeDecimals: false,
              customColor: sts.isDeficit && (breakdown?.hasPlan ?? true)
                  ? RiveroColors.danger
                  : null,
            ),
          const SizedBox(height: RiveroSpacing.xs),
          Text(
            // Nothing to measure against yet: say so, not "short by".
            !(breakdown?.hasPlan ?? true)
                ? 'Set up your salary plan to see this'
                : sts.isDeficit
                ? (breakdown?.overBudget ?? false
                      ? 'Short by '
                            '${CurrencyFormatter.format(-breakdown!.usable)}'
                      : 'Bills due exceed what is left by '
                            '${CurrencyFormatter.format(sts.deficitAmount)}')
                : '${isPrivacy ? '••••' : CurrencyFormatter.format(sts.effectiveSafeToSpend)}'
                      ' safe · '
                      '${awaiting ? 'waiting for salary' : '${paycycle.daysRemaining} days to payday'}',
            style: RiveroTypography.bodyMedium,
          ),
          if ((breakdown?.waitingForReview ?? 0) > 0 && !isPrivacy)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                // Counted already; Accept or Ignore below settles it.
                'Includes ${CurrencyFormatter.format(breakdown!.waitingForReview)} '
                'waiting for your Accept',
                key: const ValueKey('sts-waiting'),
                style: RiveroTypography.bodySmall.copyWith(
                  color: RiveroColors.warning,
                ),
              ),
            ),
          const SizedBox(height: RiveroSpacing.lg),
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: tone),
            duration: const Duration(milliseconds: 600),
            builder: (context, color, _) => ClipRRect(
              borderRadius: RiveroRadii.borderFull,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (1 - remaining).clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, used, _) => LinearProgressIndicator(
                  key: const ValueKey('budget-bar'),
                  value: used,
                  minHeight: 6,
                  backgroundColor: RiveroColors.surfaceInteractive,
                  valueColor: AlwaysStoppedAnimation<Color>(color ?? tone),
                ),
              ),
            ),
          ),
          const SizedBox(height: RiveroSpacing.sm),
          Text(
            isPrivacy
                ? '•••• left of ••••'
                : limit > 0
                ? (left > limit
                      ? '${CurrencyFormatter.format(left)} left · '
                            '${CurrencyFormatter.format(limit)} planned'
                      : '${CurrencyFormatter.format(left)} left of '
                            '${CurrencyFormatter.format(limit)}')
                : 'No spending budget set',
            style: RiveroTypography.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReliabilityDot extends StatelessWidget {
  const _ReliabilityDot({required this.reliability});

  final BalanceReliability reliability;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (reliability) {
      BalanceReliability.verified => (RiveroColors.success, 'Verified'),
      BalanceReliability.estimated => (RiveroColors.warning, 'Estimated'),
      BalanceReliability.stale => (RiveroColors.danger, 'Stale'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: RiveroTypography.labelSmall.copyWith(color: color)),
      ],
    );
  }
}
