import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Section listing recent ledger transactions with status tags and counterparty details.
class RecentActivityList extends ConsumerWidget {
  const RecentActivityList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentTransactionsProvider);
    final isPrivacy = ref.watch(privacyModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'RECENT ACTIVITY',
              style: RiveroTypography.labelSmall.copyWith(
                letterSpacing: 1.5,
                color: RiveroColors.textMuted,
              ),
            ),
            Text(
              'Encrypted Ledger',
              style: RiveroTypography.bodySmall.copyWith(
                color: RiveroColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: RiveroSpacing.md),

        recentAsync.when(
          loading: () => const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => RiveroCard(
            child: Text(
              'Failed to load recent activity: $err',
              style: RiveroTypography.bodySmall.copyWith(
                color: RiveroColors.danger,
              ),
            ),
          ),
          data: (transactions) {
            if (transactions.isEmpty) {
              return RiveroCard(
                padding: const EdgeInsets.all(RiveroSpacing.xl),
                child: Center(
                  child: Text(
                    'No transaction activity recorded yet.',
                    style: RiveroTypography.bodySmall,
                  ),
                ),
              );
            }

            return Column(
              children: transactions.take(10).map((txn) {
                final isDebit = txn.amountMinorUnits < 0;
                final formatted = CurrencyFormatter.format(
                  txn.amountMinorUnits.abs(),
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
                  child: RiveroCard(
                    padding: const EdgeInsets.all(RiveroSpacing.md),
                    child: Row(
                      children: [
                        // Category Icon Avatar
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: RiveroColors.surfaceInteractive,
                            borderRadius: RiveroRadii.borderMd,
                          ),
                          child: Icon(
                            _iconForCategory(txn.category),
                            size: 20,
                            color: RiveroColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: RiveroSpacing.md),

                        // Merchant & Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                txn.merchant,
                                style: RiveroTypography.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: RiveroSpacing.xxs),
                              Row(
                                children: [
                                  Text(
                                    txn.category,
                                    style: RiveroTypography.bodySmall,
                                  ),
                                  const SizedBox(width: RiveroSpacing.xs),
                                  Text('·', style: RiveroTypography.bodySmall),
                                  const SizedBox(width: RiveroSpacing.xs),
                                  _stateBadge(txn.transactionState),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Amount & Time
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (isPrivacy)
                              Text('••••', style: RiveroTypography.monoLarge)
                            else
                              Text(
                                isDebit ? '-$formatted' : '+$formatted',
                                style: RiveroTypography.monoMedium.copyWith(
                                  color: isDebit
                                      ? RiveroColors.textPrimary
                                      : RiveroColors.investmentAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            const SizedBox(height: RiveroSpacing.xxs),
                            Text(
                              _timeString(txn.transactionTimestamp),
                              style: RiveroTypography.bodySmall.copyWith(
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _stateBadge(TransactionState state) {
    final Color color;
    final String label;

    switch (state) {
      case TransactionState.confirmed:
        color = RiveroColors.investmentAccent;
        label = 'Confirmed';
      case TransactionState.needsReview:
        color = RiveroColors.salaryAccent;
        label = 'Review';
      case TransactionState.reconciled:
        color = RiveroColors.savingsAccent;
        label = 'Reconciled';
      case TransactionState.ignored:
        color = RiveroColors.textMuted;
        label = 'Ignored';
      case TransactionState.duplicate:
        color = RiveroColors.mandateWarning;
        label = 'Duplicate';
      case TransactionState.reversed:
        color = RiveroColors.expenseAccent;
        label = 'Reversed';
      case TransactionState.detected:
      case TransactionState.parsed:
      case TransactionState.failed:
        color = RiveroColors.textMuted;
        label = state.name;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: RiveroRadii.borderXs,
      ),
      child: Text(
        label,
        style: RiveroTypography.monoSmall.copyWith(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  IconData _iconForCategory(String? category) {
    final lower = category?.toLowerCase() ?? '';
    if (lower.contains('food') || lower.contains('dining')) {
      return Icons.restaurant;
    }
    if (lower.contains('grocer')) {
      return Icons.shopping_basket_outlined;
    }
    if (lower.contains('transport') || lower.contains('uber')) {
      return Icons.directions_car_outlined;
    }
    if (lower.contains('subscript') || lower.contains('entert')) {
      return Icons.movie_outlined;
    }
    if (lower.contains('invest')) {
      return Icons.trending_up_rounded;
    }
    if (lower.contains('salary')) {
      return Icons.account_balance_wallet_outlined;
    }
    return Icons.receipt_long_outlined;
  }

  String _timeString(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
