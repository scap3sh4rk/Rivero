import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/engine/spending_summary.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/core/utils/tags.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/features/settings/screens/categories_screen.dart';
import 'package:rivero/features/transactions/screens/analytics_screen.dart';
import 'package:rivero/features/transactions/widgets/activity_row.dart';
import 'package:rivero/features/transactions/widgets/spending_overview.dart';

/// Activity: every transaction, newest first, with search and a type filter.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum ActivityFilter { all, expenses, income, transfers }

/// Activity search and filter live here (not in widget state) so the back
/// button can clear them before leaving the tab.
final activityQueryProvider = StateProvider<String>((ref) => '');
final activityFilterProvider = StateProvider<ActivityFilter>(
  (ref) => ActivityFilter.all,
);

/// A date filter (inclusive first and last day), or null for any date.
final activityRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

/// Quick date ranges and labels for the Activity filter.
abstract final class ActivityRanges {
  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTimeRange today(DateTime now) =>
      DateTimeRange(start: day(now), end: day(now));

  static DateTimeRange yesterday(DateTime now) {
    final y = day(now).subtract(const Duration(days: 1));
    return DateTimeRange(start: y, end: y);
  }

  static DateTimeRange last7(DateTime now) => DateTimeRange(
    start: day(now).subtract(const Duration(days: 6)),
    end: day(now),
  );

  /// The whole calendar month containing [anyDay].
  static DateTimeRange month(DateTime anyDay) => DateTimeRange(
    start: DateTime(anyDay.year, anyDay.month),
    end: DateTime(anyDay.year, anyDay.month + 1, 0),
  );

  static bool contains(DateTimeRange r, DateTime t) =>
      !t.isBefore(r.start) && t.isBefore(r.end.add(const Duration(days: 1)));

  static String label(DateTimeRange r, DateTime now) {
    final f = DateFormat('d MMM');
    if (r.start == r.end) {
      if (r.start == day(now)) return 'Today';
      if (r == yesterday(now)) return 'Yesterday';
      return DateFormat('d MMM yyyy').format(r.start);
    }
    final fullMonth = r == month(r.start);
    if (fullMonth) return DateFormat('MMMM yyyy').format(r.start);
    return '${f.format(r.start)} – ${DateFormat('d MMM yyyy').format(r.end)}';
  }

  /// "Today", "Yesterday" or "Sat, 14 Nov" for a day heading.
  static String heading(DateTime d, DateTime now) {
    final t = day(now);
    if (d == t) return 'Today';
    if (d == t.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat(d.year == t.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy')
        .format(d);
  }
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  ActivityFilter get _filter => ref.read(activityFilterProvider);
  String get _query => ref.read(activityQueryProvider);
  late final _search = TextEditingController(text: _query);

  void _setQuery(String v) {
    if (_search.text != v) _search.text = v;
    ref.read(activityQueryProvider.notifier).state = v;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const Set<TransactionType> _transferTypes = {
    TransactionType.internalTransfer,
    TransactionType.bucketFunding,
    TransactionType.investmentContribution,
    TransactionType.investmentRedemption,
    TransactionType.creditCardSettlement,
    TransactionType.walletTopup,
    TransactionType.balanceAdjustment,
    TransactionType.lending,
    TransactionType.borrowing,
    TransactionType.repayment,
    TransactionType.reimbursement,
    TransactionType.atmWithdrawal,
  };

  bool _matches(LedgerTransaction t) {
    final range = ref.read(activityRangeProvider);
    if (range != null &&
        !ActivityRanges.contains(range, t.transactionTimestamp)) {
      return false;
    }
    final q = _query.trim().toLowerCase();
    // "#goa" is a tag: only entries tagged exactly that.
    if (RegExp(r'^#\S+$').hasMatch(q)) {
      if (!tagsIn(t.userNotes).contains(q.substring(1))) return false;
    } else if (q.isNotEmpty &&
        !'${t.merchant} ${t.category} ${t.userNotes ?? ''}'
            .toLowerCase()
            .contains(q)) {
      return false;
    }
    return switch (_filter) {
      ActivityFilter.all => true,
      // Same rule as the spending totals and Analytics.
      ActivityFilter.expenses => SpendingSummary.isSpending(t),
      ActivityFilter.income =>
        t.amountMinorUnits > 0 &&
            !t.isInternalTransfer &&
            t.transactionType == TransactionType.income,
      ActivityFilter.transfers =>
        t.isInternalTransfer || _transferTypes.contains(t.transactionType),
    };
  }

  DateTimeRange? get _range => ref.read(activityRangeProvider);
  set _range(DateTimeRange? r) =>
      ref.read(activityRangeProvider.notifier).state = r;

  void _openFilter() {
    final now = DateTime.now();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RiveroColors.surface,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RiveroSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Type', style: RiveroTypography.titleMedium),
              const SizedBox(height: RiveroSpacing.sm),
              Wrap(
                spacing: RiveroSpacing.sm,
                children: [
                  for (final f in ActivityFilter.values)
                    ChoiceChip(
                      label: Text(switch (f) {
                        ActivityFilter.all => 'All',
                        ActivityFilter.expenses => 'Expenses',
                        ActivityFilter.income => 'Income',
                        ActivityFilter.transfers => 'Transfers',
                      }),
                      selected: _filter == f,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      onSelected: (_) {
                        ref.read(activityFilterProvider.notifier).state = f;
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
              const SizedBox(height: RiveroSpacing.xl),
              Text('Date', style: RiveroTypography.titleMedium),
              const SizedBox(height: RiveroSpacing.sm),
              Wrap(
                spacing: RiveroSpacing.sm,
                runSpacing: RiveroSpacing.xs,
                children: [
                  _rangeChip(ctx, 'Any date', null),
                  _rangeChip(ctx, 'Today', ActivityRanges.today(now)),
                  _rangeChip(ctx, 'Yesterday', ActivityRanges.yesterday(now)),
                  _rangeChip(ctx, 'Last 7 days', ActivityRanges.last7(now)),
                  _rangeChip(ctx, 'This month', ActivityRanges.month(now)),
                  _rangeChip(
                    ctx,
                    'Last month',
                    ActivityRanges.month(DateTime(now.year, now.month - 1)),
                  ),
                  ActionChip(
                    key: const ValueKey('pick-day'),
                    avatar: const Icon(Icons.today_rounded, size: 16),
                    label: const Text('Pick a day'),
                    shape: const StadiumBorder(),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: now,
                        firstDate: DateTime(now.year - 5),
                        lastDate: now,
                      );
                      if (d == null) return;
                      _range = DateTimeRange(
                        start: ActivityRanges.day(d),
                        end: ActivityRanges.day(d),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  ActionChip(
                    key: const ValueKey('pick-range'),
                    avatar: const Icon(Icons.date_range_rounded, size: 16),
                    label: const Text('From – to'),
                    shape: const StadiumBorder(),
                    onPressed: () async {
                      final r = await showDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(now.year - 5),
                        lastDate: now,
                        initialDateRange: _range,
                      );
                      if (r == null) return;
                      _range = DateTimeRange(
                        start: ActivityRanges.day(r.start),
                        end: ActivityRanges.day(r.end),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
              const SizedBox(height: RiveroSpacing.lg),
              Text('A month', style: RiveroTypography.bodySmall),
              const SizedBox(height: RiveroSpacing.xs),
              Wrap(
                spacing: RiveroSpacing.sm,
                runSpacing: RiveroSpacing.xs,
                children: [
                  for (var i = 0; i < 12; i++)
                    _rangeChip(
                      ctx,
                      DateFormat('MMM yyyy')
                          .format(DateTime(now.year, now.month - i)),
                      ActivityRanges.month(DateTime(now.year, now.month - i)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rangeChip(BuildContext ctx, String label, DateTimeRange? r) =>
      ChoiceChip(
        label: Text(label),
        selected: _range == r,
        showCheckmark: false,
        shape: const StadiumBorder(),
        onSelected: (_) {
          _range = r;
          Navigator.pop(ctx);
        },
      );

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(allTransactionsStreamProvider).value ?? const [];
    final privacy = ref.watch(privacyModeProvider);
    ref
      ..watch(activityQueryProvider)
      ..watch(activityFilterProvider)
      ..watch(activityRangeProvider)
      ..listen(activityQueryProvider, (_, v) {
        if (_search.text != v) _search.text = v;
      });
    // "Ignore" means not a transaction: it leaves Activity (the row stays
    // stored, so the same message is recognised and never asked again).
    final shown = txns
        .where((t) => t.transactionState != TransactionState.ignored)
        .where(_matches)
        .toList();
    final range = ref.watch(activityRangeProvider);
    final now = DateTime.now();
    // A heading before each new day, with what was spent that day.
    final rows = <Object>[];
    final daySpend = <DateTime, int>{};
    DateTime? lastDay;
    for (final t in shown) {
      final d = ActivityRanges.day(t.transactionTimestamp);
      if (d != lastDay) {
        rows.add(d);
        lastDay = d;
      }
      rows.add(t);
      if (t.amountMinorUnits < 0 &&
          SpendingSummary.applied(t) &&
          SpendingSummary.isSpending(t)) {
        daySpend[d] = (daySpend[d] ?? 0) - t.amountMinorUnits;
      }
    }
    final categories = ref.watch(logCategoriesProvider);
    // Tags in use, most used first: tap one to see only those entries.
    final tagCount = <String, int>{};
    for (final t in txns) {
      for (final tag in tagsIn(t.userNotes)) {
        tagCount[tag] = (tagCount[tag] ?? 0) + 1;
      }
    }
    final tags = tagCount.keys.toList()
      ..sort((a, b) => tagCount[b]!.compareTo(tagCount[a]!));

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Activity',
        actions: [
          IconButton(
            key: const ValueKey('open-analytics'),
            tooltip: 'Analytics',
            onPressed: () => AnalyticsScreen.open(context),
            icon: const Icon(Icons.insights_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RiveroSpacing.xl,
              0,
              RiveroSpacing.xl,
              RiveroSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: _setQuery,
                    decoration: InputDecoration(
                      hintText: 'Search, notes or #tags',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey('clear-search'),
                              tooltip: 'Clear search',
                              onPressed: () => _setQuery(''),
                              icon: const Icon(Icons.close_rounded),
                            ),
                      contentPadding: EdgeInsets.zero,
                      filled: false,
                      border: OutlineInputBorder(
                        borderRadius: RiveroRadii.borderFull,
                        borderSide: BorderSide(
                          color: RiveroColors.borderMedium,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: RiveroRadii.borderFull,
                        borderSide: BorderSide(
                          color: RiveroColors.borderMedium,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: RiveroSpacing.sm),
                IconButton.outlined(
                  tooltip: 'Filter',
                  onPressed: _openFilter,
                  icon: Icon(
                    Icons.tune_rounded,
                    color: _filter == ActivityFilter.all && range == null
                        ? RiveroColors.textPrimary
                        : RiveroColors.salaryAccent,
                  ),
                ),
              ],
            ),
          ),
          if (tags.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: RiveroSpacing.xl,
                ),
                children: [
                  for (final tag in tags.take(20))
                    Padding(
                      padding: const EdgeInsets.only(right: RiveroSpacing.sm),
                      child: ChoiceChip(
                        key: ValueKey('tag-$tag'),
                        label: Text('#$tag'),
                        selected: _query.trim().toLowerCase() == '#$tag',
                        showCheckmark: false,
                        shape: const StadiumBorder(),
                        onSelected: (on) => _setQuery(on ? '#$tag' : ''),
                      ),
                    ),
                ],
              ),
            ),
          if (range != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RiveroSpacing.xl,
                0,
                RiveroSpacing.xl,
                RiveroSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  key: const ValueKey('range-chip'),
                  avatar: const Icon(Icons.event_rounded, size: 16),
                  label: Text(ActivityRanges.label(range, now)),
                  onPressed: _openFilter,
                  deleteIcon: const Icon(
                    Icons.close_rounded,
                    key: ValueKey('range-clear'),
                    size: 18,
                  ),
                  onDeleted: () => _range = null,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                RiveroSpacing.xl,
                0,
                RiveroSpacing.xl,
                RiveroSpacing.huge + MediaQuery.paddingOf(context).bottom,
              ),
              // Row 0: the spending overview (for the chosen dates, or this
              // pay cycle). Then each day starts with its own heading.
              itemCount: rows.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  final browsing =
                      _query.isEmpty && _filter == ActivityFilter.all;
                  return Column(
                    children: [
                      if (browsing && txns.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: RiveroSpacing.sm,
                          ),
                          child: SpendingOverview(
                            onCategoryTap: _setQuery,
                            range: range,
                          ),
                        ),
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(RiveroSpacing.huge),
                          child: Text(
                            txns.isEmpty ? 'Nothing logged yet' : 'No matches',
                            style: RiveroTypography.bodyMedium,
                          ),
                        ),
                    ],
                  );
                }
                final row = rows[i - 1];
                if (row is DateTime) {
                  final spent = daySpend[row] ?? 0;
                  return Padding(
                    key: ValueKey('day-$row'),
                    padding: const EdgeInsets.only(
                      top: RiveroSpacing.lg,
                      bottom: RiveroSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            ActivityRanges.heading(row, now),
                            style: RiveroTypography.labelLarge.copyWith(
                              color: RiveroColors.textSecondary,
                            ),
                          ),
                        ),
                        if (spent > 0)
                          Text(
                            privacy
                                ? '••••'
                                : 'Spent ${CurrencyFormatter.format(spent)}',
                            style: RiveroTypography.bodySmall,
                          ),
                      ],
                    ),
                  );
                }
                final t = row as LedgerTransaction;
                return ActivityRow(
                  t,
                  privacy: privacy,
                  tint: t.amountMinorUnits > 0
                      ? RiveroColors.success
                      : categoryColor(t.category, categories),
                ).animate().fadeIn(duration: 220.ms);
              },
            ),
          ),
        ],
      ),
    );
  }
}
