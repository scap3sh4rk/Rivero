import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/financial_amount_text.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/home/widgets/sts_breakdown_sheet.dart';

/// The single hero of the app: one large Safe-to-Spend number on a card
/// whose background is a battery of how much of the month's spending is
/// left, green to amber to red as it runs down.
class SafeToSpendHeroCard extends ConsumerWidget {
  const SafeToSpendHeroCard({super.key});

  /// The battery's colour for how much of the month's spending is left:
  /// green while there is plenty, amber as it runs down, red near empty.
  static Color fillFor(double remaining) {
    final r = remaining.clamp(0.0, 1.0);
    if (r >= 0.5) return RiveroColors.success;
    if (r >= 0.2) {
      return Color.lerp(
        RiveroColors.warning,
        RiveroColors.success,
        (r - 0.2) / 0.3,
      )!;
    }
    return Color.lerp(RiveroColors.danger, RiveroColors.warning, r / 0.2)!;
  }

  /// Text drawn over the fill: near-black or white, whichever stands out
  /// more against [fill] (WCAG contrast), so it is always readable.
  static Color onFillFor(Color fill) {
    const dark = Color(0xFF0B0B0F);
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (la > lb ? la + 0.05 : lb + 0.05) /
          (la > lb ? lb + 0.05 : la + 0.05);
    }

    return contrast(fill, dark) >= contrast(fill, Colors.white)
        ? dark
        : Colors.white;
  }

  static bool _spendingOutOfDate(WidgetRef ref) {
    final stale = ref.watch(balanceToUpdateProvider);
    if (stale.isEmpty) return false;
    final buckets = ref.watch(allAllocationBucketsProvider).value ?? const [];
    return buckets.any(
      (b) =>
          b.role == AccountRole.expense &&
          stale.contains(b.linkedPhysicalAccountId),
    );
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
    final hasPlan = breakdown?.hasPlan ?? true;
    // The battery level: how much of the month's spending is left (the
    // number turns red on its own when bills due take more than that).
    // Empty with no plan yet; hidden amounts hide the level too.
    final remaining = !hasPlan || limit <= 0 || isPrivacy
        ? 0.0
        : (left / limit).clamp(0.0, 1.0);

    // Everything about today's number lives in one card, and the card is
    // the battery: its background fills with what is left of the month's
    // spending, like the iPhone battery widget.
    final content = Padding(
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
              // Only when the number may be out of date (no "Verified").
              if (sts.reliability != BalanceReliability.verified) ...[
                _ReliabilityDot(reliability: sts.reliability),
                const SizedBox(width: RiveroSpacing.xs),
              ],
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
          // The spending account's balance stopped at zero on a payment:
          // the number rests on a balance that needs the user's update.
          if (_spendingOutOfDate(ref))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Update your spending account balance (Accounts) for a '
                'reliable number',
                key: const ValueKey('sts-update-balance'),
                style: RiveroTypography.bodySmall.copyWith(
                  color: RiveroColors.warning,
                ),
              ),
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
    return RiveroCard(
      key: const ValueKey('sts-card'),
      isElevated: true,
      onTap: () => StsBreakdownSheet.show(context),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: RiveroRadii.card,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: remaining),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, level, _) =>
              BatteryFill(level: level, child: content),
        ),
      ),
    );
  }
}

/// A card background that fills from the left like a battery, with a
/// gradient in the level's colour. Over the filled part the content is
/// recoloured, through a hard-edged shader, in one colour that stands out
/// against the fill; elsewhere it keeps its own colours. Text stays readable
/// wherever the edge of the fill falls.
class BatteryFill extends StatelessWidget {
  const BatteryFill({required this.level, required this.child, super.key});

  /// 0 = empty, 1 = full.
  final double level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = level.clamp(0.0, 1.0);
    final fill = SafeToSpendHeroCard.fillFor(l);
    final onFill = SafeToSpendHeroCard.onFillFor(fill);
    return Stack(
      children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              key: const ValueKey('budget-fill'),
              widthFactor: l,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color.lerp(fill, Colors.black, 0.18)!, fill],
                  ),
                ),
              ),
            ),
          ),
        ),
        ShaderMask(
          // srcATop paints the shader only where the content has pixels:
          // the on-fill colour left of the edge, nothing (own colours) right.
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            colors: [onFill, onFill, Colors.transparent, Colors.transparent],
            stops: [0, l, l, 1],
          ).createShader(bounds),
          child: child,
        ),
      ],
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
