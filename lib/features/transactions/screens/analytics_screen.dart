import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/spending_summary.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/category_icons.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/account_color.dart';
import 'package:rivero/design_system/widgets/picker.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/features/settings/screens/categories_screen.dart';
import 'package:rivero/features/transactions/widgets/activity_row.dart';

/// Month-by-month spending: a trend line, then categories or top spends.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const AnalyticsScreen()));

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  static const _months = 6;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _accountId; // null = all accounts
  bool _topSpends = false;

  List<DateTime> get _range {
    final now = DateTime.now();
    return [
      for (var i = _months - 1; i >= 0; i--) DateTime(now.year, now.month - i),
    ];
  }

  SpendingSummary _summary(
    List<LedgerTransaction> txns,
    Map<String, int> shares,
    DateTime month,
  ) => SpendingSummary.of(
    txns,
    start: month,
    end: DateTime(
      month.year,
      month.month + 1,
    ).subtract(const Duration(milliseconds: 1)),
    othersShare: shares,
  );

  @override
  Widget build(BuildContext context) {
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final accounts =
        ref.watch(activePhysicalAccountsProvider).value ?? const [];
    final all = ref.watch(allTransactionsStreamProvider).value ?? const [];
    final txns = _accountId == null
        ? all
        : all.where((t) => t.physicalAccountId == _accountId).toList();
    final shares = DuesService.othersShareByTransaction(
      ref.watch(duesProvider).value ?? const [],
    );
    final categories = ref.watch(logCategoriesProvider);
    final months = _range;
    final totals = [for (final m in months) _summary(txns, shares, m).total];
    final current = _summary(txns, shares, _month);
    final accountName =
        accounts.where((a) => a.id == _accountId).firstOrNull?.name ??
        'All accounts';

    final monthStart = _month;
    final monthEnd = DateTime(_month.year, _month.month + 1);
    final top =
        txns
            .where(
              (t) =>
                  t.amountMinorUnits < 0 &&
                  SpendingSummary.applied(t) &&
                  SpendingSummary.isSpending(t) &&
                  !t.transactionTimestamp.isBefore(monthStart) &&
                  t.transactionTimestamp.isBefore(monthEnd),
            )
            .toList()
          ..sort((a, b) => a.amountMinorUnits.compareTo(b.amountMinorUnits));

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Analytics',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: RiveroSpacing.huge),
        children: [
          Center(
            child: TextButton.icon(
              key: const ValueKey('analytics-account'),
              onPressed: () async {
                final picked = await showPicker<String?>(
                  context,
                  title: 'Show spending for',
                  selected: _accountId,
                  options: [
                    const PickerOption(null, 'All accounts'),
                    for (final a in accounts)
                      PickerOption(
                        a.id,
                        a.name,
                        leading: ColorDot(accountColor(a)),
                      ),
                  ],
                );
                if (picked != null) setState(() => _accountId = picked.value);
              },
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(accountName, style: RiveroTypography.titleMedium),
            ),
          ),
          Center(
            child: Text(
              money(current.total),
              key: const ValueKey('analytics-total'),
              style: RiveroTypography.financialHero,
            ),
          ),
          Center(
            child: Text(
              DateFormat('MMMM y').format(_month),
              style: RiveroTypography.bodySmall,
            ),
          ),
          const SizedBox(height: RiveroSpacing.xl),
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _TrendPainter(
                values: totals,
                selected: months.indexOf(_month),
                line: RiveroColors.accent,
                guide: RiveroColors.borderHighlight,
                highlight: RiveroColors.surfaceElevated,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: RiveroSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final m in months)
                ChoiceChip(
                  key: ValueKey('month-${m.month}'),
                  label: Text(DateFormat('MMM').format(m)),
                  selected: m == _month,
                  showCheckmark: false,
                  shape: const StadiumBorder(),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _month = m),
                ),
            ],
          ),
          if (!privacy && totals.any((t) => t > 0))
            Center(
              child: Text(
                'Average ${money(totals.fold<int>(0, (a, b) => a + b) ~/ totals.length)} a month',
                style: RiveroTypography.bodySmall,
              ),
            ),
          const SizedBox(height: RiveroSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.xl),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Categories')),
                ButtonSegment(value: true, label: Text('Top spends')),
              ],
              selected: {_topSpends},
              onSelectionChanged: (s) => setState(() => _topSpends = s.first),
            ),
          ),
          const SizedBox(height: RiveroSpacing.md),
          if (!_topSpends) ...[
            if (current.byCategory.isEmpty)
              Padding(
                padding: const EdgeInsets.all(RiveroSpacing.xl),
                child: Text(
                  'No spending this month',
                  style: RiveroTypography.bodyMedium,
                ),
              ),
            for (final e in current.byCategory)
              _CategoryLine(
                name: e.key,
                amount: money(e.value),
                share: e.value / current.total,
                color: categoryColor(e.key, categories),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.xl),
              child: Column(
                children: [
                  for (final t in top.take(10))
                    ActivityRow(
                      t,
                      privacy: privacy,
                      tint: categoryColor(t.category, categories),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryLine extends StatelessWidget {
  const _CategoryLine({
    required this.name,
    required this.amount,
    required this.share,
    required this.color,
  });

  final String name;
  final String amount;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RiveroSpacing.xl,
        vertical: RiveroSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: RiveroColors.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(iconForLabel(name), color: color, size: 20),
          ),
          const SizedBox(width: RiveroSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: RiveroTypography.bodyLarge),
                const SizedBox(height: RiveroSpacing.xs),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: share.clamp(0.04, 1.0),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: RiveroRadii.borderFull,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: RiveroSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount, style: RiveroTypography.labelLarge),
              Text(
                '${(share * 100).round()}%',
                style: RiveroTypography.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Monthly totals as a smooth line with a dashed average and the selected
/// month highlighted.
class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.selected,
    required this.line,
    required this.guide,
    required this.highlight,
  });

  final List<int> values;
  final int selected;
  final Color line;
  final Color guide;
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<int>(1, (m, v) => v > m ? v : m);
    final slot = size.width / values.length;
    Offset at(int i) => Offset(
      slot * i + slot / 2,
      size.height - 16 - (values[i] / maxV) * (size.height - 32),
    );

    if (selected >= 0) {
      final x = at(selected).dx;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 18, 0, 36, size.height),
          const Radius.circular(18),
        ),
        Paint()..color = highlight,
      );
    }

    final avg = values.fold<int>(0, (a, b) => a + b) / values.length;
    final avgY = size.height - 16 - (avg / maxV) * (size.height - 32);
    final dash = Paint()
      ..color = guide
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, avgY), Offset(x + 4, avgY), dash);
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = at(i - 1);
      final p1 = at(i);
      final mid = (p0.dx + p1.dx) / 2;
      path.cubicTo(mid, p0.dy, mid, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    if (selected >= 0) {
      canvas
        ..drawCircle(at(selected), 7, Paint()..color = line)
        ..drawCircle(at(selected), 3, Paint()..color = highlight);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values || old.selected != selected || old.line != line;
}
