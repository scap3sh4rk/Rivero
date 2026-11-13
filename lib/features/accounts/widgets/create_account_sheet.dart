import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Interactive modal sheet to create a new physical bank, cash, or credit account.
class CreateAccountSheet extends ConsumerStatefulWidget {
  const CreateAccountSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateAccountSheet(),
    );
  }

  @override
  ConsumerState<CreateAccountSheet> createState() => _CreateAccountSheetState();
}

class _CreateAccountSheetState extends ConsumerState<CreateAccountSheet> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  final _maskController = TextEditingController();
  final _balanceController = TextEditingController(text: '0');
  final _creditLimitController = TextEditingController(text: '0');

  String _selectedAccountType = StandardAccountTypes.savings;
  bool _isLiability = false;

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _maskController.dispose();
    _balanceController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  void _onAccountTypeChanged(String? type) {
    if (type == null) return;
    setState(() {
      _selectedAccountType = type;
      if (type == StandardAccountTypes.creditCard ||
          type == StandardAccountTypes.creditLine ||
          type == StandardAccountTypes.loan ||
          type == StandardAccountTypes.overdraft) {
        _isLiability = true;
      }
    });
  }

  Future<void> _promptNewCustomType() async {
    final textController = TextEditingController();
    final customType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: RiveroColors.surfaceElevated,
        title: Text(
          'Add Custom Account Type',
          style: RiveroTypography.titleMedium,
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: RiveroTypography.bodyLarge,
          decoration: InputDecoration(
            hintText: 'e.g. Crypto Vault, Chit Fund, ESOP',
            hintStyle: TextStyle(color: RiveroColors.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final trimmed = textController.text.trim();
              if (trimmed.isNotEmpty) {
                Navigator.pop(context, trimmed);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (customType != null && customType.isNotEmpty) {
      final currentTypes = ref.read(customAccountTypesProvider);
      if (!currentTypes.contains(customType)) {
        ref.read(customAccountTypesProvider.notifier).state = [
          ...currentTypes,
          customType,
        ];
      }
      setState(() {
        _selectedAccountType = customType;
      });
    }
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final institution = _institutionController.text.trim();
    final mask = _maskController.text.trim().replaceAll(RegExp(r'\D'), '');

    final balanceRupees =
        double.tryParse(_balanceController.text.trim()) ?? 0.0;
    var balanceMinorUnits = (balanceRupees * 100).round();

    // If it's a liability/credit card with an initial balance entered as a positive spend,
    // in the ledger liabilities are stored as negative numbers (e.g. -₹14,250).
    if (_isLiability && balanceMinorUnits > 0) {
      balanceMinorUnits = -balanceMinorUnits;
    }

    final limitRupees =
        double.tryParse(_creditLimitController.text.trim()) ?? 0.0;
    final creditLimitMinorUnits = (limitRupees * 100).round();

    final now = DateTime.now();
    final accountId = 'acc-${now.millisecondsSinceEpoch}';

    final db = ref.read(databaseProvider);
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: drift.Value(accountId),
        name: drift.Value(name),
        institution: drift.Value(institution),
        accountMask: drift.Value(mask.isNotEmpty ? mask : '0000'),
        accountType: drift.Value(_selectedAccountType),
        balanceMinorUnits: drift.Value(balanceMinorUnits),
        creditLimitMinorUnits: drift.Value(creditLimitMinorUnits),
        isActive: const drift.Value(true),
        isLiability: drift.Value(_isLiability),
        createdAt: drift.Value(now),
        updatedAt: drift.Value(now),
      ),
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Account "$name" created successfully!'),
          backgroundColor: RiveroColors.investmentAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableTypes = ref.watch(customAccountTypesProvider);

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
                // Drag handle
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

                // Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Create New Account',
                      style: RiveroTypography.titleLarge,
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: RiveroColors.textMuted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.lg),

                // Account Name
                Text(
                  'Account Friendly Name',
                  style: RiveroTypography.labelSmall,
                ),
                const SizedBox(height: RiveroSpacing.xs),
                TextFormField(
                  controller: _nameController,
                  style: RiveroTypography.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Primary HDFC Salary, ICICI Amazon Pay',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter an account name'
                      : null,
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Bank / Institution & Last 4 digits
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Institution / Bank',
                            style: RiveroTypography.labelSmall,
                          ),
                          const SizedBox(height: RiveroSpacing.xs),
                          TextFormField(
                            controller: _institutionController,
                            style: RiveroTypography.bodyLarge,
                            decoration: const InputDecoration(
                              hintText: 'e.g. HDFC, ICICI, Cash',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Institution required'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: RiveroSpacing.md),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Last 4 Digits',
                            style: RiveroTypography.labelSmall,
                          ),
                          const SizedBox(height: RiveroSpacing.xs),
                          TextFormField(
                            controller: _maskController,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            style: RiveroTypography.bodyLarge,
                            decoration: const InputDecoration(
                              hintText: '4012',
                              counterText: '',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Account Type Selector + Add Custom Type button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Account Type', style: RiveroTypography.labelSmall),
                    GestureDetector(
                      onTap: _promptNewCustomType,
                      child: Text(
                        '+ Custom Type',
                        style: RiveroTypography.labelSmall.copyWith(
                          color: RiveroColors.salaryAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.xs),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedAccountType,
                  dropdownColor: RiveroColors.surfaceElevated,
                  style: RiveroTypography.bodyLarge,
                  decoration: const InputDecoration(),
                  items: availableTypes.map((type) {
                    return DropdownMenuItem<String>(
                      value: type,
                      child: Row(
                        children: [
                          Icon(
                            StandardAccountTypes.getIcon(type),
                            size: 18,
                            color: RiveroColors.textSecondary,
                          ),
                          const SizedBox(width: RiveroSpacing.sm),
                          Text(type),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: _onAccountTypeChanged,
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Liability / Credit Card switch
                RiveroCard(
                  padding: const EdgeInsets.all(RiveroSpacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.credit_card_rounded,
                            color: RiveroColors.liabilityAccent,
                            size: 20,
                          ),
                          const SizedBox(width: RiveroSpacing.sm),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Credit Card / Line of Credit',
                                style: RiveroTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Enables 10%/30% utilization score tracking',
                                style: RiveroTypography.bodySmall.copyWith(
                                  fontSize: 11,
                                  color: RiveroColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Switch(
                        value: _isLiability,
                        activeColor: RiveroColors.liabilityAccent,
                        onChanged: (val) {
                          setState(() {
                            _isLiability = val;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: RiveroSpacing.md),

                // Balance & Credit Limit
                if (_isLiability) ...[
                  Text('Credit Limit (₹)', style: RiveroTypography.labelSmall),
                  const SizedBox(height: RiveroSpacing.xs),
                  TextFormField(
                    controller: _creditLimitController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: RiveroTypography.bodyLarge,
                    decoration: const InputDecoration(
                      prefixText: '₹ ',
                      hintText: '150000',
                      helperText:
                          'Track 10% safe limit and 30% score impact threshold',
                    ),
                    validator: (v) {
                      final parsed = double.tryParse(v ?? '');
                      if (parsed == null || parsed <= 0) {
                        return 'Please enter a valid credit limit';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: RiveroSpacing.md),
                  Text(
                    'Current Outstanding / Spent (₹)',
                    style: RiveroTypography.labelSmall,
                  ),
                  const SizedBox(height: RiveroSpacing.xs),
                  TextFormField(
                    controller: _balanceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: RiveroTypography.bodyLarge,
                    decoration: const InputDecoration(
                      prefixText: '₹ ',
                      hintText: '0.00',
                    ),
                  ),
                ] else ...[
                  Text(
                    'Initial Balance (₹)',
                    style: RiveroTypography.labelSmall,
                  ),
                  const SizedBox(height: RiveroSpacing.xs),
                  TextFormField(
                    controller: _balanceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: RiveroTypography.bodyLarge,
                    decoration: const InputDecoration(
                      prefixText: '₹ ',
                      hintText: '50000.00',
                    ),
                    validator: (v) {
                      if (v == null || double.tryParse(v.trim()) == null) {
                        return 'Please enter a valid balance';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: RiveroSpacing.xl),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RiveroColors.investmentAccent,
                      foregroundColor: RiveroColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(RiveroRadii.md),
                      ),
                    ),
                    onPressed: _saveAccount,
                    child: Text(
                      'Save Account',
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
