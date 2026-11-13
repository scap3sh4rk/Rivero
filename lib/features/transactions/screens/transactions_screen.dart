import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/transactions/widgets/create_transaction_sheet.dart';

/// Comprehensive expense tracker and ledger transaction stream with multi-criteria filtering.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionType? _selectedTypeFilter;
  String? _selectedCategoryFilter;

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(allTransactionsStreamProvider);
    final accountsAsync = ref.watch(activePhysicalAccountsProvider);
    final isPrivacy = ref.watch(privacyModeProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Transactions',
        subtitle: 'Encrypted Expense Ledger',
        actions: [
          IconButton(
            tooltip: 'Log Transaction',
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: RiveroColors.expenseAccent,
            ),
            onPressed: () => CreateTransactionSheet.show(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: RiveroColors.expenseAccent,
        foregroundColor: RiveroColors.background,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Log Expense',
          style: RiveroTypography.titleMedium.copyWith(
            color: RiveroColors.background,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: () => CreateTransactionSheet.show(context),
      ),
      body: Column(
        children: [
          // Filter Chips Horizontal Scroll
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: RiveroSpacing.lg,
              vertical: RiveroSpacing.sm,
            ),
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'All',
                  isSelected: _selectedTypeFilter == null,
                  onSelected: () {
                    setState(() => _selectedTypeFilter = null);
                  },
                ),
                const SizedBox(width: RiveroSpacing.sm),
                _buildFilterChip(
                  label: 'Expenses',
                  isSelected: _selectedTypeFilter == TransactionType.expense,
                  onSelected: () {
                    setState(
                      () => _selectedTypeFilter = TransactionType.expense,
                    );
                  },
                ),
                const SizedBox(width: RiveroSpacing.sm),
                _buildFilterChip(
                  label: 'Income',
                  isSelected: _selectedTypeFilter == TransactionType.income,
                  onSelected: () {
                    setState(
                      () => _selectedTypeFilter = TransactionType.income,
                    );
                  },
                ),
                const SizedBox(width: RiveroSpacing.sm),
                _buildFilterChip(
                  label: 'Transfers',
                  isSelected:
                      _selectedTypeFilter == TransactionType.internalTransfer,
                  onSelected: () {
                    setState(
                      () => _selectedTypeFilter =
                          TransactionType.internalTransfer,
                    );
                  },
                ),
              ],
            ),
          ),

          // Transaction Stream List
          Expanded(
            child: transactionsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    RiveroColors.expenseAccent,
                  ),
                ),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Failed to load transactions: $err',
                  style: RiveroTypography.bodyMedium.copyWith(
                    color: RiveroColors.danger,
                  ),
                ),
              ),
              data: (allTxns) {
                final accounts = accountsAsync.value ?? [];

                // Apply type and category filters
                var filtered = allTxns;
                if (_selectedTypeFilter != null) {
                  filtered = filtered
                      .where((t) => t.transactionType == _selectedTypeFilter)
                      .toList();
                }
                if (_selectedCategoryFilter != null) {
                  filtered = filtered
                      .where((t) => t.category == _selectedCategoryFilter)
                      .toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: RiveroColors.textMuted,
                        ),
                        const SizedBox(height: RiveroSpacing.md),
                        Text(
                          'No Transactions Found',
                          style: RiveroTypography.titleMedium,
                        ),
                        const SizedBox(height: RiveroSpacing.xs),
                        Text(
                          'Transactions logged or captured from notifications will appear here.',
                          style: RiveroTypography.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  color: RiveroColors.expenseAccent,
                  backgroundColor: RiveroColors.surfaceElevated,
                  onRefresh: () async {
                    ref.invalidate(allTransactionsStreamProvider);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      RiveroSpacing.lg,
                      RiveroSpacing.sm,
                      RiveroSpacing.lg,
                      80,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: RiveroSpacing.xs),
                    itemBuilder: (context, index) {
                      final txn = filtered[index];
                      final isExpense = txn.amountMinorUnits < 0;
                      final account = accounts
                          .where((a) => a.id == txn.physicalAccountId)
                          .firstOrNull;

                      final accountLabel = account != null
                          ? '${account.institution} ••${account.accountMask}'
                          : 'Account';

                      return Dismissible(
                        key: ValueKey(txn.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(
                            right: RiveroSpacing.lg,
                          ),
                          decoration: BoxDecoration(
                            color: RiveroColors.danger.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(RiveroRadii.md),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                        onDismissed: (_) async {
                          final db = ref.read(databaseProvider);
                          await db.transactionsDao.deleteTransaction(txn.id);
                          // Reverse the balance adjustment
                          await db.accountsDao.adjustAccountBalance(
                            txn.physicalAccountId,
                            -txn.amountMinorUnits,
                          );
                        },
                        child: RiveroCard(
                          padding: const EdgeInsets.all(RiveroSpacing.md),
                          child: Row(
                            children: [
                              // Category icon
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isExpense
                                      ? RiveroColors.expenseAccent.withValues(
                                          alpha: 0.12,
                                        )
                                      : RiveroColors.investmentAccent
                                            .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(
                                    RiveroRadii.md,
                                  ),
                                ),
                                child: Icon(
                                  _categoryIcon(txn.category),
                                  size: 20,
                                  color: isExpense
                                      ? RiveroColors.expenseAccent
                                      : RiveroColors.investmentAccent,
                                ),
                              ),
                              const SizedBox(width: RiveroSpacing.md),

                              // Description & metadata
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      txn.merchant.isNotEmpty
                                          ? txn.merchant
                                          : txn.category,
                                      style: RiveroTypography.bodyLarge
                                          .copyWith(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          txn.category,
                                          style: RiveroTypography.bodySmall
                                              .copyWith(
                                                fontSize: 11,
                                                color:
                                                    RiveroColors.textSecondary,
                                              ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          '·',
                                          style: TextStyle(
                                            color: RiveroColors.textMuted,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          accountLabel,
                                          style: RiveroTypography.bodySmall
                                              .copyWith(
                                                fontSize: 11,
                                                color: RiveroColors.textMuted,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Amount
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (isPrivacy)
                                    Text(
                                      '••••••',
                                      style: RiveroTypography.monoMedium,
                                    )
                                  else
                                    Text(
                                      CurrencyFormatter.format(
                                        txn.amountMinorUnits,
                                      ),
                                      style: RiveroTypography.monoMedium
                                          .copyWith(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: isExpense
                                                ? RiveroColors.textPrimary
                                                : RiveroColors.investmentAccent,
                                          ),
                                    ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatTime(txn.transactionTimestamp),
                                    style: RiveroTypography.labelSmall.copyWith(
                                      fontSize: 10,
                                      color: RiveroColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: RiveroTypography.labelSmall.copyWith(
        color: isSelected ? RiveroColors.background : RiveroColors.textPrimary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      backgroundColor: RiveroColors.surfaceElevated,
      selectedColor: RiveroColors.expenseAccent,
      checkmarkColor: RiveroColors.background,
      side: BorderSide(
        color: isSelected
            ? RiveroColors.expenseAccent
            : RiveroColors.borderSubtle,
      ),
      onSelected: (_) => onSelected(),
    );
  }

  IconData _categoryIcon(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('food') || lower.contains('dining')) {
      return Icons.restaurant_rounded;
    }
    if (lower.contains('grocer')) return Icons.shopping_basket_rounded;
    if (lower.contains('shop')) return Icons.shopping_bag_rounded;
    if (lower.contains('transport') ||
        lower.contains('fuel') ||
        lower.contains('cab')) {
      return Icons.directions_car_rounded;
    }
    if (lower.contains('entertain') || lower.contains('movie')) {
      return Icons.movie_creation_outlined;
    }
    if (lower.contains('bill') || lower.contains('utilit')) {
      return Icons.receipt_long_rounded;
    }
    if (lower.contains('health') || lower.contains('med')) {
      return Icons.medical_services_outlined;
    }
    if (lower.contains('salary') || lower.contains('income')) {
      return Icons.account_balance_wallet_rounded;
    }
    if (lower.contains('invest') || lower.contains('sip')) {
      return Icons.trending_up_rounded;
    }
    if (lower.contains('transfer')) return Icons.swap_horiz_rounded;
    return Icons.credit_card_rounded;
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
