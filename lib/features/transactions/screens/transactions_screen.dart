import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';

/// Activity: every transaction, newest first, with search and a type filter.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum _Filter { all, expenses, income, transfers }

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';

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
      _Filter.all => true,
      _Filter.expenses =>
        t.amountMinorUnits < 0 && !_transferTypes.contains(t.transactionType),
      _Filter.income =>
        t.amountMinorUnits > 0 && !_transferTypes.contains(t.transactionType),
      _Filter.transfers => _transferTypes.contains(t.transactionType),
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
              for (final f in _Filter.values)
                ChoiceChip(
                  label: Text(switch (f) {
                    _Filter.all => 'All',
                    _Filter.expenses => 'Expenses',
                    _Filter.income => 'Income',
                    _Filter.transfers => 'Transfers',
                  }),
                  selected: _filter == f,
                  showCheckmark: false,
                  shape: const StadiumBorder(),
                  onSelected: (_) {
                    setState(() => _filter = f);
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
    final shown = txns.where(_matches).toList();

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: const RiveroAppBar(title: 'Activity'),
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
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search transactions',
                      prefixIcon: const Icon(Icons.search_rounded),
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
                    color: _filter == _Filter.all
                        ? RiveroColors.textPrimary
                        : RiveroColors.salaryAccent,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      txns.isEmpty ? 'Nothing logged yet' : 'No matches',
                      style: RiveroTypography.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: RiveroSpacing.xl,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (_, i) =>
                        _ActivityRow(shown[i], privacy: privacy),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.t, {required this.privacy});

  final LedgerTransaction t;
  final bool privacy;

  @override
  Widget build(BuildContext context) {
    final credit = t.amountMinorUnits > 0;
    final pending = t.transactionState == TransactionState.needsReview;
    final ignored = t.transactionState == TransactionState.ignored;
    final amount = CurrencyFormatter.format(t.amountMinorUnits.abs());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RiveroSpacing.md),
      child: Row(
        children: [
          BankBadge(name: t.merchant, size: 48, circle: true),
          const SizedBox(width: RiveroSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RiveroTypography.titleMedium.copyWith(fontSize: 15),
                ),
                Text(
                  '${DateFormat("d MMM ''yy").format(t.transactionTimestamp)}'
                  ' · ${pending ? 'Needs review' : t.category}',
                  style: RiveroTypography.bodySmall.copyWith(
                    color: pending ? RiveroColors.warning : null,
                  ),
                ),
              ],
            ),
          ),
          Text(
            privacy ? '••••' : '${credit ? '+' : ''}$amount',
            style: RiveroTypography.titleMedium.copyWith(
              fontSize: 15,
              color: ignored
                  ? RiveroColors.textMuted
                  : credit
                  ? RiveroColors.success
                  : RiveroColors.textPrimary,
              decoration: ignored ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}
