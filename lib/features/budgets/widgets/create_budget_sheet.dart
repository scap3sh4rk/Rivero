import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Modal bottom sheet to create or configure a monthly purpose-driven allocation bucket.
class CreateBudgetSheet extends ConsumerStatefulWidget {
  const CreateBudgetSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateBudgetSheet(),
    );
  }

  @override
  ConsumerState<CreateBudgetSheet> createState() => _CreateBudgetSheetState();
}

class _CreateBudgetSheetState extends ConsumerState<CreateBudgetSheet> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _priorityController = TextEditingController(text: '1');

  AccountRole _selectedRole = AccountRole.expense;
  String? _selectedAccountId;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  Future<void> _saveBudget() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _titleController.text.trim();
    final amountRupees = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final allocatedMinorUnits = (amountRupees * 100).round();
    final priority = int.tryParse(_priorityController.text.trim()) ?? 1;

    final now = DateTime.now();
    final bucketId = 'bucket-${now.millisecondsSinceEpoch}';

    final accountId = _selectedAccountId;
    final db = ref.read(databaseProvider);
    await db.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: drift.Value(bucketId),
        name: drift.Value(name),
        role: drift.Value(_selectedRole),
        targetMinorUnits: drift.Value(allocatedMinorUnits),
        allocatedMinorUnits: drift.Value(allocatedMinorUnits),
        spentMinorUnits: const drift.Value(0),
        linkedPhysicalAccountId: accountId != null
            ? drift.Value(accountId)
            : const drift.Value.absent(),
        priorityOrder: drift.Value(priority),
        createdAt: drift.Value(now),
        updatedAt: drift.Value(now),
      ),
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Monthly budget purpose "$name" created!'),
          backgroundColor: RiveroColors.investmentAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(activePhysicalAccountsProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: RiveroColors.surface,
          borderRadius: BorderRadius.vertical(
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
                    Text(
                      'New Budget Purpose',
                      style: RiveroTypography.titleLarge,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: RiveroColors.textMuted,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.lg),

                // Purpose Title
                Text(
                  'Purpose / Bucket Name',
                  style: RiveroTypography.labelSmall,
                ),
                const SizedBox(height: RiveroSpacing.xs),
                TextFormField(
                  controller: _titleController,
                  style: RiveroTypography.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Rent, Groceries, Mutual Funds SIP, Bills',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter a purpose name'
                      : null,
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Financial Role / Category
                Text(
                  'Allocation Purpose Role',
                  style: RiveroTypography.labelSmall,
                ),
                const SizedBox(height: RiveroSpacing.xs),
                DropdownButtonFormField<AccountRole>(
                  isExpanded: true,
                  value: _selectedRole,
                  dropdownColor: RiveroColors.surfaceElevated,
                  style: RiveroTypography.bodyLarge,
                  decoration: const InputDecoration(),
                  items: const [
                    DropdownMenuItem(
                      value: AccountRole.expense,
                      child: Text('Living Expense (Daily/Monthly)'),
                    ),
                    DropdownMenuItem(
                      value: AccountRole.investment,
                      child: Text('Investment (SIP / Stocks / Gold)'),
                    ),
                    DropdownMenuItem(
                      value: AccountRole.savings,
                      child: Text('Savings (Emergency Fund / FD)'),
                    ),
                    DropdownMenuItem(
                      value: AccountRole.custom,
                      child: Text('Custom Allocation'),
                    ),
                  ],
                  onChanged: (role) {
                    if (role != null) setState(() => _selectedRole = role);
                  },
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Monthly Allocation Amount (₹)
                Text(
                  'Monthly Target / Allocation Amount (₹)',
                  style: RiveroTypography.labelSmall,
                ),
                const SizedBox(height: RiveroSpacing.xs),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: RiveroTypography.bodyLarge,
                  decoration: const InputDecoration(
                    prefixText: '₹ ',
                    hintText: '25000',
                    helperText: 'How much goes to this purpose every month',
                  ),
                  validator: (v) {
                    final parsed = double.tryParse(v ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Please enter a valid monthly amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Linked Physical Account
                Text(
                  'Deducts From Account (Optional)',
                  style: RiveroTypography.labelSmall,
                ),
                const SizedBox(height: RiveroSpacing.xs),
                accountsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (accounts) {
                    return DropdownButtonFormField<String?>(
                      isExpanded: true,
                      value: _selectedAccountId,
                      dropdownColor: RiveroColors.surfaceElevated,
                      style: RiveroTypography.bodyLarge,
                      decoration: const InputDecoration(),
                      items: [
                        const DropdownMenuItem<String?>(
                          child: Text('No specific account linked'),
                        ),
                        ...accounts.map(
                          (acc) => DropdownMenuItem<String?>(
                            value: acc.id,
                            child: Text(
                              '${acc.name} (${acc.institution} ••${acc.accountMask})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedAccountId = val);
                      },
                    );
                  },
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Priority Order
                Text(
                  'Waterfall Priority (1 = Top Priority)',
                  style: RiveroTypography.labelSmall,
                ),
                const SizedBox(height: RiveroSpacing.xs),
                TextFormField(
                  controller: _priorityController,
                  keyboardType: TextInputType.number,
                  style: RiveroTypography.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: '1',
                    helperText:
                        'Highest priority purposes receive salary funds first',
                  ),
                ),
                const SizedBox(height: RiveroSpacing.xl),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RiveroColors.salaryAccent,
                      foregroundColor: RiveroColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(RiveroRadii.md),
                      ),
                    ),
                    onPressed: _saveBudget,
                    child: Text(
                      'Save Purpose Bucket',
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
