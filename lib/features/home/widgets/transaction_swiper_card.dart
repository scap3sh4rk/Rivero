import 'package:flutter/material.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Card widget representing a pending ledger transaction inside the triage swiper stack.
class TransactionSwiperCard extends StatelessWidget {
  const TransactionSwiperCard({
    required this.transaction,
    super.key,
    this.percentX = 0,
    this.onConfirm,
    this.onIgnore,
  });

  final LedgerTransaction transaction;
  final int percentX;
  final VoidCallback? onConfirm;
  final VoidCallback? onIgnore;

  @override
  Widget build(BuildContext context) {
    final isConfirming = percentX > 15;
    final isIgnoring = percentX < -15;

    final borderColor = isConfirming
        ? RiveroColors.investmentAccent
        : isIgnoring
        ? RiveroColors.danger
        : RiveroColors.borderHighlight;

    final amountAbs = transaction.amountMinorUnits.abs();
    final formattedAmount = CurrencyFormatter.format(amountAbs);
    final isDebit = transaction.amountMinorUnits < 0;

    return RiveroCard(
      isElevated: true,
      borderColor: borderColor,
      padding: const EdgeInsets.all(RiveroSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Category and Swipe Hint Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: RiveroSpacing.sm,
                  vertical: RiveroSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: RiveroColors.surfaceInteractive,
                  borderRadius: RiveroRadii.borderSm,
                ),
                child: Text(
                  transaction.category,
                  style: RiveroTypography.bodySmall.copyWith(
                    color: RiveroColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (isConfirming)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RiveroSpacing.sm,
                    vertical: RiveroSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: RiveroColors.investmentAccent.withValues(alpha: 0.2),
                    borderRadius: RiveroRadii.borderSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: RiveroColors.investmentAccent,
                      ),
                      const SizedBox(width: RiveroSpacing.xs),
                      Text(
                        'CONFIRM',
                        style: RiveroTypography.labelSmall.copyWith(
                          color: RiveroColors.investmentAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else if (isIgnoring)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RiveroSpacing.sm,
                    vertical: RiveroSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: RiveroColors.danger.withValues(alpha: 0.2),
                    borderRadius: RiveroRadii.borderSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cancel_rounded,
                        size: 14,
                        color: RiveroColors.danger,
                      ),
                      const SizedBox(width: RiveroSpacing.xs),
                      Text(
                        'IGNORE',
                        style: RiveroTypography.labelSmall.copyWith(
                          color: RiveroColors.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Icon(Icons.swipe, size: 14, color: RiveroColors.textMuted),
                    const SizedBox(width: RiveroSpacing.xs),
                    Text('Swipe to triage', style: RiveroTypography.bodySmall),
                  ],
                ),
            ],
          ),

          const Spacer(),

          // Merchant name / Counterparty
          Text(
            transaction.merchant,
            style: RiveroTypography.displayMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: RiveroSpacing.xs),

          // Amount display
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                isDebit ? '-$formattedAmount' : '+$formattedAmount',
                style: RiveroTypography.financialLarge.copyWith(
                  color: isDebit
                      ? RiveroColors.textPrimary
                      : RiveroColors.investmentAccent,
                ),
              ),
              const SizedBox(width: RiveroSpacing.sm),
              Text(
                isDebit ? 'Debited' : 'Credited',
                style: RiveroTypography.bodySmall,
              ),
            ],
          ),

          const SizedBox(height: RiveroSpacing.md),

          // Reference & Mask
          if (transaction.referenceNumber != null) ...[
            Text(
              'Ref: ${transaction.referenceNumber}',
              style: RiveroTypography.monoSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: RiveroSpacing.xs),
          ],

          Text(
            _formatTimestamp(transaction.transactionTimestamp),
            style: RiveroTypography.bodySmall,
          ),

          const Spacer(),

          // Direct action buttons (alternative to gesture swipe)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onIgnore,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Ignore'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RiveroColors.textSecondary,
                    side: BorderSide(color: RiveroColors.borderMedium),
                    padding: const EdgeInsets.symmetric(
                      vertical: RiveroSpacing.md,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: RiveroRadii.borderMd,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: RiveroSpacing.md),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Confirm'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RiveroColors.investmentAccent,
                    foregroundColor: RiveroColors.background,
                    padding: const EdgeInsets.symmetric(
                      vertical: RiveroSpacing.md,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: RiveroRadii.borderMd,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final month = _monthName(dt.month);
    return '$day $month · $hour:$minute $period';
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }
}
