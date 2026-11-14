import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/category_icons.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/features/transactions/widgets/transaction_detail_sheet.dart';

/// One transaction row: round tinted initial, title, date · category,
/// optional note, amount. Tapping opens its details.
class ActivityRow extends StatelessWidget {
  const ActivityRow(
    this.t, {
    super.key,
    required this.privacy,
    required this.tint,
  });

  final LedgerTransaction t;
  final bool privacy;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final credit = t.amountMinorUnits > 0;
    final pending = t.transactionState == TransactionState.needsReview;
    final ignored = t.transactionState == TransactionState.ignored;
    final amount = CurrencyFormatter.format(t.amountMinorUnits.abs());
    final note = t.userNotes;
    return InkWell(
      borderRadius: RiveroRadii.borderLg,
      onTap: () => TransactionDetailSheet.show(context, t),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: RiveroSpacing.md,
          horizontal: RiveroSpacing.xs,
        ),
        child: Row(
          children: [
            _RowIcon(
              icon: iconForLabel(t.merchant, category: t.category),
              specific: hasSpecificIcon(t.merchant, category: t.category),
              name: t.merchant,
              tint: tint,
            ),
            const SizedBox(width: RiveroSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.merchant,
                    maxLines: 2,
                    style: RiveroTypography.titleMedium.copyWith(fontSize: 15),
                  ),
                  Text(
                    '${DateFormat("d MMM ''yy").format(t.transactionTimestamp)}'
                    ' · ${pending ? 'Needs review' : t.category}',
                    style: RiveroTypography.bodySmall.copyWith(
                      color: pending ? RiveroColors.warning : null,
                    ),
                  ),
                  if (note != null)
                    Text(
                      note,
                      maxLines: 2,
                      style: RiveroTypography.bodySmall.copyWith(
                        fontStyle: FontStyle.italic,
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
      ),
    );
  }
}

/// Round tinted icon for the row; falls back to initials when nothing
/// specific matches (for example a person's name).
class _RowIcon extends StatelessWidget {
  const _RowIcon({
    required this.icon,
    required this.specific,
    required this.name,
    required this.tint,
  });

  final IconData icon;
  final bool specific;
  final String name;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    if (!specific) {
      return BankBadge(name: name, size: 48, circle: true, color: tint);
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: tint, size: 22),
    );
  }
}
