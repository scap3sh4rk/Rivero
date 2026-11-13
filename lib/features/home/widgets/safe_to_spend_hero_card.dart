import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/financial_amount_text.dart';

/// The single hero of the app: one large Safe-to-Spend number with a pill
/// showing how much of the expense budget is left. The pill shifts from
/// green to amber to red as funds run down.
class SafeToSpendHeroCard extends ConsumerWidget {
  const SafeToSpendHeroCard({super.key});

  /// Colour for the fraction of budget remaining (1 = full, 0 = empty).
  static Color toneFor(double remaining, {bool deficit = false}) {
    if (deficit) return RiveroColors.danger;
    final r = remaining.clamp(0.0, 1.0);
    return r >= 0.5
        ? Color.lerp(RiveroColors.warning, RiveroColors.success, (r - 0.5) * 2)!
        : Color.lerp(RiveroColors.danger, RiveroColors.warning, r * 2)!;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stsAsync = ref.watch(liveSafeToSpendResultProvider);
    final buckets = ref.watch(allAllocationBucketsProvider).value ?? const [];
    final isPrivacy = ref.watch(privacyModeProvider);
    final paycycle = ref.watch(currentPaycycleProvider);

    final sts = stsAsync.value;
    if (sts == null) return const SizedBox(height: 220);

    var limit = 0;
    var spent = 0;
    for (final b in buckets.where((b) => b.role == AccountRole.expense)) {
      limit += b.allocatedMinorUnits + b.carryOverMinorUnits;
      spent += b.spentMinorUnits;
    }
    final remaining = limit > 0
        ? (limit - spent) / limit
        : (sts.isDeficit ? 0.0 : 1.0);
    final tone = toneFor(remaining, deficit: sts.isDeficit);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'SAFE TO SPEND',
              style: RiveroTypography.labelSmall.copyWith(
                letterSpacing: 2,
                color: RiveroColors.textMuted,
              ),
            ),
            const SizedBox(width: RiveroSpacing.sm),
            _ReliabilityDot(reliability: sts.reliability),
          ],
        ),
        const SizedBox(height: RiveroSpacing.md),
        if (isPrivacy)
          Text('••••••••', style: RiveroTypography.financialHero)
        else
          FinancialAmountText(
            minorUnits: sts.effectiveSafeToSpend,
            size: FinancialAmountSize.hero,
            isAnimated: true,
            includeDecimals: false,
            customColor: sts.isDeficit ? RiveroColors.danger : null,
          ),
        const SizedBox(height: RiveroSpacing.xs),
        Text(
          sts.isDeficit
              ? 'Commitments exceed balance by '
                    '${CurrencyFormatter.format(sts.deficitAmount)}'
              : '${CurrencyFormatter.format(sts.dailySpendingPace)} a day · '
                    '${paycycle.daysRemaining} days left',
          style: RiveroTypography.bodyMedium,
        ),
        const SizedBox(height: RiveroSpacing.xl),
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: tone),
          duration: const Duration(milliseconds: 600),
          builder: (context, color, _) => _BudgetPill(
            color: color ?? tone,
            remaining: remaining.clamp(0.0, 1.0),
            label: isPrivacy
                ? '•••• of ••••'
                : limit > 0
                ? '${CurrencyFormatter.format(spent)} spent of '
                      '${CurrencyFormatter.format(limit)}'
                : 'No expense budget set',
          ),
        ),
      ],
    );
  }
}

class _BudgetPill extends StatelessWidget {
  const _BudgetPill({
    required this.color,
    required this.remaining,
    required this.label,
  });

  final Color color;
  final double remaining;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RiveroSpacing.lg,
        vertical: RiveroSpacing.md,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: RiveroRadii.borderFull,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: RiveroTypography.labelSmall.copyWith(color: color),
          ),
          const SizedBox(height: RiveroSpacing.sm),
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: RiveroRadii.borderFull,
              child: LinearProgressIndicator(
                value: remaining,
                minHeight: 4,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
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
