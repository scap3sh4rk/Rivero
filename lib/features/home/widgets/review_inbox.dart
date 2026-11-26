import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/home/widgets/quick_review_sheet.dart';
import 'package:rivero/features/home/widgets/unreadable_sheet.dart';
import 'package:rivero/features/transactions/widgets/undo.dart';

/// Captured transactions the app was not sure about. Buttons, not swipes, so
/// it never fights the page swipe. Hidden entirely when there is nothing.
class ReviewInbox extends ConsumerWidget {
  const ReviewInbox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A card bill's card side follows its bank side; it is not asked twice.
    final pending = <LedgerTransaction>[
      for (final t
          in ref.watch(pendingReviewTransactionsProvider).value ??
              const <LedgerTransaction>[])
        if (!t.id.startsWith('cc-') &&
            !(t.isInternalTransfer &&
                t.linkedTransactionId != null &&
                t.amountMinorUnits > 0 &&
                t.transactionType == TransactionType.creditCardSettlement))
          t,
    ];
    final unreadable = ref.watch(unreadableMessagesProvider).value?.length ?? 0;
    if (pending.isEmpty && unreadable == 0) return const SizedBox.shrink();
    final unreadableCard = unreadable == 0
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
            child: RiveroCard(
              key: const ValueKey('unreadable-card'),
              onTap: () => UnreadableSheet.show(context),
              child: Row(
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    color: RiveroColors.warning,
                  ),
                  const SizedBox(width: RiveroSpacing.md),
                  Expanded(
                    child: Text(
                      unreadable == 1
                          ? '1 bank message to check'
                          : '$unreadable bank messages to check',
                      style: RiveroTypography.bodyLarge,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: RiveroColors.textSecondary,
                  ),
                ],
              ),
            ),
          );
    if (pending.isEmpty) return unreadableCard!;
    final privacy = ref.watch(privacyModeProvider);

    Future<void> ignore(LedgerTransaction t) => ignoreWithUndo(context, t.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'To review · ${pending.length}',
          style: RiveroTypography.titleMedium,
        ),
        const SizedBox(height: RiveroSpacing.xs),
        Text(
          'Captured from your notifications. Accept what is right.',
          style: RiveroTypography.bodySmall,
        ),
        const SizedBox(height: RiveroSpacing.md),
        ?unreadableCard,
        for (final t in pending.take(3))
          Padding(
            key: ValueKey(t.id),
            padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
            child: RiveroCard(
              onTap: () => QuickReviewSheet.show(context, t.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      BankBadge(name: t.merchant, size: 40, circle: true),
                      const SizedBox(width: RiveroSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.merchant, style: RiveroTypography.bodyLarge),
                            Text(
                              DateFormat('d MMM, h:mm a')
                                  .format(t.transactionTimestamp),
                              style: RiveroTypography.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        privacy
                            ? '••••'
                            : '${t.amountMinorUnits > 0 ? '+' : ''}'
                                  '${CurrencyFormatter.format(t.amountMinorUnits.abs())}',
                        style: RiveroTypography.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: RiveroSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => ignore(t),
                          style: OutlinedButton.styleFrom(
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('Ignore'),
                        ),
                      ),
                      const SizedBox(width: RiveroSpacing.sm),
                      Expanded(
                        child: FilledButton(
                          // Accept asks for the category right here, on
                          // Home (and an optional description).
                          onPressed: () => QuickReviewSheet.show(context, t.id),
                          style: FilledButton.styleFrom(
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('Accept'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (pending.length > 3)
          Text(
            '${pending.length - 3} more after these',
            style: RiveroTypography.bodySmall,
          ),
      ],
    );
  }
}
