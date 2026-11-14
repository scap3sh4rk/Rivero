import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/spending_summary.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/account_color.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/settings/screens/categories_screen.dart';

/// "You've spent ₹X since payday": a day-by-day chart for this pay cycle and
/// the categories it went to. Tapping a category filters the list below.
class SpendingOverview extends ConsumerStatefulWidget {
  const SpendingOverview({required this.onCategoryTap, super.key, this.range});

  final ValueChanged<String> onCategoryTap;

  /// Dates chosen in Activity's filter (inclusive); null = this pay cycle.
  final DateTimeRange? range;

  @override
  ConsumerState<SpendingOverview> createState() => _SpendingOverviewState();
}

class _SpendingOverviewState extends ConsumerState<SpendingOverview> {
  // Collapsed by default: just the month's total until asked for more.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(allTransactionsStreamProvider).value ?? const [];
    final cycle = ref.watch(currentPaycycleProvider);
    final privacy = ref.watch(privacyModeProvider);
    final now = DateTime.now();
    final r = widget.range;
    final start = r?.start ?? cycle.cycleStartDate;
    // The whole last day counts; never past now.
    final rangeEnd = r == null
        ? now
        : DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
    final end = rangeEnd.isAfter(now) ? now : rangeEnd;
    final s = SpendingSummary.of(
      txns,
      start: start,
      end: end,
      othersShare: DuesService.othersShareByTransaction(
        ref.watch(duesProvider).value ?? const [],
      ),
      toHome: ref.watch(toHomeProvider),
    );
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final daysSoFar = s.byDay.length;

    final f = DateFormat('d MMM');
    final title = r == null
        ? 'Spent since ${f.format(cycle.cycleStartDate)}'
        : r.start == r.end
        ? 'Spent on ${f.format(r.start)}'
        : 'Spent ${f.format(r.start)} – ${f.format(r.end)}';
    final totalDays = r == null
        ? cycle.totalDaysInCycle
        : r.end.difference(r.start).inDays + 1;

    // Compact: one line with the amount; details only when opened.
    return RiveroCard(
      isElevated: true,
      padding: const EdgeInsets.symmetric(
        horizontal: RiveroSpacing.lg,
        vertical: RiveroSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('overview-toggle'),
            borderRadius: RiveroRadii.borderMd,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: RiveroTypography.bodySmall),
                      Text(
                        money(s.total),
                        key: const ValueKey('spent-total'),
                        style: RiveroTypography.financialMedium,
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: RiveroColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.total > 0)
                        Text(
                          '${money(s.total ~/ daysSoFar)} a day on average',
                          style: RiveroTypography.bodySmall,
                        ),
                      const SizedBox(height: RiveroSpacing.lg),
                      SizedBox(
                        height: 64,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _DailyBars(
                            s.byDay,
                            totalDays: totalDays,
                            bar: RiveroColors.textMuted,
                            today: RiveroColors.textPrimary,
                            empty: RiveroColors.surfaceInteractive,
                          ),
                        ),
                      ),
                      if (s.byCategory.isNotEmpty) ...[
                        const SizedBox(height: RiveroSpacing.lg),
                        for (final e in s.byCategory.take(5))
                          _CategoryBar(
                            color: categoryColor(
                              e.key,
                              ref.watch(logCategoriesProvider),
                            ),
                            name: e.key,
                            amount: money(e.value),
                            share: e.value / s.total,
                            onTap: () => widget.onCategoryTap(e.key),
                          ),
                        if (s.byCategory.length > 5)
                          Text(
                            '+ ${s.byCategory.length - 5} more categories',
                            style: RiveroTypography.bodySmall,
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.color,
    required this.name,
    required this.amount,
    required this.share,
    required this.onTap,
  });

  final Color color;
  final String name;
  final String amount;
  final double share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: RiveroRadii.borderSm,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: RiveroSpacing.xs),
        child: Column(
          children: [
            Row(
              children: [
                ColorDot(color),
                const SizedBox(width: RiveroSpacing.sm),
                Expanded(child: Text(name, style: RiveroTypography.bodyMedium)),
                Text(amount, style: RiveroTypography.labelLarge),
              ],
            ),
            const SizedBox(height: RiveroSpacing.xs),
            ClipRRect(
              borderRadius: RiveroRadii.borderFull,
              child: LinearProgressIndicator(
                value: share,
                minHeight: 4,
                backgroundColor: RiveroColors.surfaceInteractive,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One bar per day of the cycle; days still to come are faint stubs.
class _DailyBars extends CustomPainter {
  _DailyBars(
    this.values, {
    required this.totalDays,
    required this.bar,
    required this.today,
    required this.empty,
  });

  final List<int> values;
  final int totalDays;
  final Color bar;
  final Color today;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final days = totalDays < values.length ? values.length : totalDays;
    if (days == 0) return;
    final slot = size.width / days;
    final w = (slot * 0.6).clamp(1.5, 10.0);
    final maxV = values.fold<int>(1, (m, v) => v > m ? v : m);
    for (var i = 0; i < days; i++) {
      final v = i < values.length ? values[i] : 0;
      final h = v == 0 ? 2.0 : (v / maxV * size.height).clamp(3.0, size.height);
      final paint = Paint()
        ..color = i >= values.length
            ? empty
            : i == values.length - 1
            ? today
            : (v == 0 ? empty : bar);
      final x = i * slot + (slot - w) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, w, h),
          Radius.circular(w / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DailyBars old) =>
      old.values != values || old.totalDays != totalDays;
}
