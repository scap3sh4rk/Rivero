import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
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
  };

  bool _matches(LedgerTransaction t) {
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty &&
        !'${t.merchant} ${t.category}'.toLowerCase().contains(q)) {
      return false;
    }
    return switch (_filter) {
      ActivityFilter.all => true,
      ActivityFilter.expenses =>
        t.amountMinorUnits < 0 && !_transferTypes.contains(t.transactionType),
      ActivityFilter.income =>
        t.amountMinorUnits > 0 && !_transferTypes.contains(t.transactionType),
      ActivityFilter.transfers => _transferTypes.contains(t.transactionType),
    };
  }

  void _openFilter() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RiveroColors.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RiveroSpacing.xl),
          child: Wrap(
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(allTransactionsStreamProvider).value ?? const [];
    final privacy = ref.watch(privacyModeProvider);
    ref
      ..watch(activityQueryProvider)
      ..watch(activityFilterProvider)
      ..listen(activityQueryProvider, (_, v) {
        if (_search.text != v) _search.text = v;
      });
    final shown = txns.where(_matches).toList();
    final categories = ref.watch(logCategoriesProvider);

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
                      hintText: 'Search transactions',
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
                    color: _filter == ActivityFilter.all
                        ? RiveroColors.textPrimary
                        : RiveroColors.salaryAccent,
                  ),
                ),
              ],
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
              // Row 0: the month overview (only when not searching/filtering).
              itemCount: shown.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  final browsing =
                      _query.isEmpty && _filter == ActivityFilter.all;
                  return Column(
                    children: [
                      if (browsing && txns.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: RiveroSpacing.md,
                          ),
                          child: SpendingOverview(onCategoryTap: _setQuery),
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
                final t = shown[i - 1];
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
