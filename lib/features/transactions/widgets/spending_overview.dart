import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/spending_summary.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// "You've spent ₹X since payday": a day-by-day chart for this pay cycle and
/// the categories it went to. Tapping a category filters the list below.
class SpendingOverview extends ConsumerWidget {
  const SpendingOverview({required this.onCategoryTap, super.key});

  final ValueChanged<String> onCategoryTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(allTransactionsStreamProvider).value ?? const [];
    final cycle = ref.watch(currentPaycycleProvider);
    final privacy = ref.watch(privacyModeProvider);
    final now = DateTime.now();
    final s = SpendingSummary.of(
      txns,
      start: cycle.cycleStartDate,
      end: now,
      othersShare: DuesService.othersShareByTransaction(
        ref.watch(duesProvider).value ?? const [],
      ),
    );
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final daysSoFar = s.byDay.length;

    return RiveroCard(
      isElevated: true,
      padding: const EdgeInsets.all(RiveroSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spent since ${DateFormat('d MMM').format(cycle.cycleStartDate)}',
            style: RiveroTypography.bodyMedium,
          ),
          const SizedBox(height: RiveroSpacing.xs),
          Text(
            money(s.total),
            key: const ValueKey('spent-total'),
            style: RiveroTypography.financialLarge,
          ),
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
                totalDays: cycle.totalDaysInCycle,
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
                name: e.key,
                amount: money(e.value),
                share: e.value / s.total,
                onTap: () => onCategoryTap(e.key),
              ),
            if (s.byCategory.length > 5)
              Text(
                '+ ${s.byCategory.length - 5} more categories',
                style: RiveroTypography.bodySmall,
              ),
          ],
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.name,
    required this.amount,
    required this.share,
    required this.onTap,
  });

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
                valueColor: AlwaysStoppedAnimation<Color>(
                  RiveroColors.textSecondary,
                ),
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
