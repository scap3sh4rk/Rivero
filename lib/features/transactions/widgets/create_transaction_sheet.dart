import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Modal bottom sheet to log a new expense, income, or transfer manually.
class CreateTransactionSheet extends ConsumerStatefulWidget {
  const CreateTransactionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateTransactionSheet(),
    );
  }

  @override
  ConsumerState<CreateTransactionSheet> createState() =>
      _CreateTransactionSheetState();
}

class _CreateTransactionSheetState
    extends ConsumerState<CreateTransactionSheet> {
  final _formKey = GlobalKey<FormState>();

  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  String? _selectedAccountId;
  String? _selectedBucketId;
  String _selectedCategory = 'Food & Dining';

  static const List<String> _categories = [
    'Food & Dining',
    'Groceries',
    'Shopping',
    'Transportation',
    'Entertainment',
    'Bills & Utilities',
    'Healthcare',
    'Subscriptions',
    'Travel',
    'Education',
    'Salary / Income',
    'Investment',
    'Transfer',
    'Other',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select an account')));
      return;
    }

    final amountRupees = double.tryParse(_amountController.text.trim()) ?? 0.0;
    var minorUnits = (amountRupees * 100).round();

    // Expenses are negative in the ledger; Income is positive
    if (_type == TransactionType.expense) {
      minorUnits = -minorUnits.abs();
    } else if (_type == TransactionType.income) {
      minorUnits = minorUnits.abs();
    }

    final merchant = _merchantController.text.trim();
    await ref
        .read(ledgerServiceProvider)
        .recordManual(
          accountId: _selectedAccountId!,
          amountMinorUnits: minorUnits,
          type: _type,
          merchant: merchant.isNotEmpty ? merchant : _selectedCategory,
          category: _selectedCategory,
          bucketId: _selectedBucketId,
        );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_type == TransactionType.expense ? "Expense" : "Income"} recorded!',
          ),
          backgroundColor: RiveroColors.investmentAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(activePhysicalAccountsProvider);
    final bucketsAsync = ref.watch(allAllocationBucketsProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: RiveroColors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(RiveroRadii.xl),
          ),
          border: Border(
            top: BorderSide(color: RiveroColors.borderHighlight, width: 1.5),
          ),
        ),
        padding: const EdgeInsets.all(RiveroSpacing.xl),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: RiveroColors.surfaceInteractive,
                      borderRadius: BorderRadius.circular(RiveroRadii.full),
                    ),
                  ),
                ),
                const SizedBox(height: RiveroSpacing.md),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Log Transaction', style: RiveroTypography.titleLarge),
                    IconButton(
                      icon: Icon(Icons.close, color: RiveroColors.textMuted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.lg),

                // Type Segment (Expense / Income / Transfer)
                SegmentedButton<TransactionType>(
                  segments: const [
                    ButtonSegment(
                      value: TransactionType.expense,
                      label: Text('Expense'),
                      icon: Icon(Icons.arrow_downward_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: TransactionType.income,
                      label: Text('Income'),
                      icon: Icon(Icons.arrow_upward_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: TransactionType.internalTransfer,
                      label: Text('Transfer'),
                      icon: Icon(Icons.swap_horiz_rounded, size: 16),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (set) {
                    setState(() => _type = set.first);
                  },
                ),
                const SizedBox(height: RiveroSpacing.lg),

                // Amount
                Text('Amount (₹)', style: RiveroTypography.labelSmall),
                const SizedBox(height: RiveroSpacing.xs),
                TextFormField(
                  controller: _amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: RiveroTypography.financialLarge,
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    hintText: '0.00',
                    prefixStyle: RiveroTypography.financialLarge.copyWith(
                      color: _type == TransactionType.expense
                          ? RiveroColors.expenseAccent
                          : RiveroColors.investmentAccent,
                    ),
                  ),
                  validator: (v) {
                    final parsed = double.tryParse(v ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Please enter a valid amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Physical Account
                Text(
                  'Paid From / To Account',
                  style: RiveroTypography.labelSmall,
                ),
                const SizedBox(height: RiveroSpacing.xs),
                accountsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (accounts) {
                    if (accounts.isEmpty) {
                      return Text(
                        'No accounts available. Create an account first.',
                        style: RiveroTypography.bodySmall.copyWith(
                          color: RiveroColors.danger,
                        ),
                      );
                    }
                    if (_selectedAccountId == null && accounts.isNotEmpty) {
                      _selectedAccountId = accounts.first.id;
                    }
                    return DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _selectedAccountId,
                      dropdownColor: RiveroColors.surfaceElevated,
                      style: RiveroTypography.bodyLarge,
                      decoration: const InputDecoration(),
                      items: accounts.map((acc) {
                        return DropdownMenuItem(
                          value: acc.id,
                          child: Text(
                            '${acc.name} (${acc.institution} ••${acc.accountMask})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (id) =>
                          setState(() => _selectedAccountId = id),
                    );
                  },
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Category & Merchant Note
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Category', style: RiveroTypography.labelSmall),
                          const SizedBox(height: RiveroSpacing.xs),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _selectedCategory,
                            dropdownColor: RiveroColors.surfaceElevated,
                            style: RiveroTypography.bodyLarge,
                            decoration: const InputDecoration(),
                            items: _categories.map((cat) {
                              return DropdownMenuItem(
                                value: cat,
                                child: Text(cat),
                              );
                            }).toList(),
                            onChanged: (cat) {
                              if (cat != null) {
                                setState(() => _selectedCategory = cat);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: RiveroSpacing.md),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Merchant / Note',
                            style: RiveroTypography.labelSmall,
                          ),
                          const SizedBox(height: RiveroSpacing.xs),
                          TextFormField(
                            controller: _merchantController,
                            style: RiveroTypography.bodyLarge,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Swiggy, Amazon',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Linked Allocation Bucket (Optional)
                if (_type == TransactionType.expense) ...[
                  Text(
                    'Deduct from Budget Purpose (Optional)',
                    style: RiveroTypography.labelSmall,
                  ),
                  const SizedBox(height: RiveroSpacing.xs),
                  bucketsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (buckets) {
                      return DropdownButtonFormField<String?>(
                        isExpanded: true,
                        value: _selectedBucketId,
                        dropdownColor: RiveroColors.surfaceElevated,
                        style: RiveroTypography.bodyLarge,
                        decoration: const InputDecoration(),
                        items: [
                          const DropdownMenuItem<String?>(
                            child: Text('Unlinked (General Expense)'),
                          ),
                          ...buckets.map((b) {
                            return DropdownMenuItem<String?>(
                              value: b.id,
                              child: Text(
                                '${b.name} (${b.role.name})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                        ],
                        onChanged: (id) =>
                            setState(() => _selectedBucketId = id),
                      );
                    },
                  ),
                  const SizedBox(height: RiveroSpacing.md),
                ],

                const SizedBox(height: RiveroSpacing.lg),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _type == TransactionType.expense
                          ? RiveroColors.expenseAccent
                          : RiveroColors.investmentAccent,
                      foregroundColor: RiveroColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(RiveroRadii.md),
                      ),
                    ),
                    onPressed: _saveTransaction,
                    child: Text(
                      'Record ${_type == TransactionType.expense ? "Expense" : "Transaction"}',
                      style: RiveroTypography.titleMedium.copyWith(
                        color: RiveroColors.background,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
