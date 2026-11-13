import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/home/widgets/transaction_swiper_card.dart';

/// Section hosting the interactive CardSwiper for fast inbox transaction triage.
class TransactionSwiperSection extends ConsumerStatefulWidget {
  const TransactionSwiperSection({super.key});

  @override
  ConsumerState<TransactionSwiperSection> createState() =>
      _TransactionSwiperSectionState();
}

class _TransactionSwiperSectionState
    extends ConsumerState<TransactionSwiperSection> {
  late final CardSwiperController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CardSwiperController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingReviewTransactionsProvider);

    return pendingAsync.when(
      loading: () => const SizedBox(
        height: 280,
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              RiveroColors.expenseAccent,
            ),
          ),
        ),
      ),
      error: (err, stack) => RiveroCard(
        borderColor: RiveroColors.danger.withValues(alpha: 0.3),
        child: Text(
          'Failed to load pending transactions: $err',
          style: RiveroTypography.bodySmall.copyWith(
            color: RiveroColors.danger,
          ),
        ),
      ),
      data: (pendingTransactions) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'INBOX TRIAGE',
                      style: RiveroTypography.labelSmall.copyWith(
                        letterSpacing: 1.5,
                        color: RiveroColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: RiveroSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: pendingTransactions.isNotEmpty
                            ? RiveroColors.salaryAccent.withValues(alpha: 0.15)
                            : RiveroColors.surfaceInteractive,
                        borderRadius: RiveroRadii.borderFull,
                      ),
                      child: Text(
                        '${pendingTransactions.length}',
                        style: RiveroTypography.labelSmall.copyWith(
                          color: pendingTransactions.isNotEmpty
                              ? RiveroColors.salaryAccent
                              : RiveroColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Swipe right: Keep · left: Skip',
                  style: RiveroTypography.bodySmall.copyWith(
                    color: RiveroColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RiveroSpacing.md),

            // Swiper Stack or Empty State
            if (pendingTransactions.isEmpty)
              _buildEmptyState()
            else
              SizedBox(
                height: 260,
                child: CardSwiper(
                  key: ValueKey('swiper-${pendingTransactions.length}'),
                  controller: _controller,
                  cardsCount: pendingTransactions.length,
                  numberOfCardsDisplayed: pendingTransactions.length > 1
                      ? (pendingTransactions.length >= 3 ? 3 : 2)
                      : 1,
                  allowedSwipeDirection: const AllowedSwipeDirection.only(
                    left: true,
                    right: true,
                  ),
                  backCardOffset: const Offset(0, 12),
                  padding: EdgeInsets.zero,
                  onSwipe: (previousIndex, currentIndex, direction) async {
                    if (previousIndex < 0 ||
                        previousIndex >= pendingTransactions.length) {
                      return false;
                    }
                    final txn = pendingTransactions[previousIndex];
                    final db = ref.read(databaseProvider);

                    if (direction == CardSwiperDirection.right) {
                      await ref.read(ledgerServiceProvider).confirm(txn.id);
                      await ref
                          .read(reconciliationServiceProvider)
                          .reconcileAll();
                    } else if (direction == CardSwiperDirection.left) {
                      await db.transactionsDao.updateTransactionState(
                        txn.id,
                        TransactionState.ignored,
                      );
                    }
                    return true;
                  },
                  cardBuilder: (context, index, percentX, percentY) {
                    if (index < 0 || index >= pendingTransactions.length) {
                      return const SizedBox.shrink();
                    }
                    final txn = pendingTransactions[index];
                    return TransactionSwiperCard(
                      transaction: txn,
                      percentX: percentX,
                      onConfirm: () =>
                          _controller.swipe(CardSwiperDirection.right),
                      onIgnore: () =>
                          _controller.swipe(CardSwiperDirection.left),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return RiveroCard(
      padding: const EdgeInsets.symmetric(
        horizontal: RiveroSpacing.xl,
        vertical: RiveroSpacing.xxl,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(RiveroSpacing.md),
              decoration: BoxDecoration(
                color: RiveroColors.investmentAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 32,
                color: RiveroColors.investmentAccent,
              ),
            ),
            const SizedBox(height: RiveroSpacing.md),
            Text('Inbox Zero', style: RiveroTypography.titleMedium),
            const SizedBox(height: RiveroSpacing.xs),
            Text(
              'All caught up! No incoming transactions pending review.',
              style: RiveroTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
