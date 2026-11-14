import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/storage/media_store.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/photo_picker.dart';
import 'package:rivero/design_system/widgets/picker.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Sheet to add, or edit when [existing] is given, a bank, cash or card account.
class CreateAccountSheet extends ConsumerStatefulWidget {
  const CreateAccountSheet({super.key, this.existing});

  final PhysicalAccount? existing;

  static Future<void> show(BuildContext context, {PhysicalAccount? existing}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateAccountSheet(existing: existing),
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
  int? _color; // null = automatic colour from the bank name
  String? _imagePath; // stored picture, or a freshly picked temp file
  bool _imageChanged = false;

  static String _rupees(int minor) {
    final v = minor.abs();
    return v % 100 == 0
        ? '${v ~/ 100}'
        : '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    if (a != null) {
      _nameController.text = a.name;
      _institutionController.text = a.institution;
      _maskController.text = a.accountMask.replaceAll(RegExp(r'\D'), '');
      _balanceController.text = _rupees(a.balanceMinorUnits);
      _creditLimitController.text = _rupees(a.creditLimitMinorUnits);
      _selectedAccountType = a.accountType;
      _isLiability = a.isLiability;
      _color = a.colorValue;
      _imagePath = a.imagePath;
      final types = ref.read(customAccountTypesProvider);
      if (!types.contains(a.accountType)) {
        ref.read(customAccountTypesProvider.notifier).state = [
          ...types,
          a.accountType,
        ];
      }
    }
  }

  /// Copies a newly picked picture into app storage; drops a removed one.
  Future<String?> _storedImage(String accountId) async {
    if (!_imageChanged) return _imagePath;
    await MediaStore.remove(widget.existing?.imagePath);
    final picked = _imagePath;
    if (picked == null) return null;
    return await MediaStore.keep(
      picked,
      folder: MediaStore.accountImages,
      name: accountId,
    );
  }

  Future<void> _remove() async {
    final a = widget.existing;
    if (a == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${a.name}?'),
        content: const Text('It is hidden from lists; past transactions stay.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(databaseProvider)
        .accountsDao
        .deactivatePhysicalAccount(a.id);
    if (mounted) Navigator.pop(context);
  }

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

    var balanceMinorUnits = parseAmountMinorUnits(
      _balanceController.text.trim().replaceAll('-', ''),
    );

    // If it's a liability/credit card with an initial balance entered as a positive spend,
    // in the ledger liabilities are stored as negative numbers (e.g. -₹14,250).
    if (_isLiability && balanceMinorUnits > 0) {
      balanceMinorUnits = -balanceMinorUnits;
    }

    final creditLimitMinorUnits = parseAmountMinorUnits(
      _creditLimitController.text.trim(),
    );

    final now = DateTime.now();
    final accountId =
        widget.existing?.id ?? 'acc-${now.millisecondsSinceEpoch}';

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
        colorValue: drift.Value(_color),
        imagePath: drift.Value(await _storedImage(accountId)),
        createdAt: drift.Value(widget.existing?.createdAt ?? now),
        updatedAt: drift.Value(now),
      ),
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existing == null ? '$name added' : '$name updated',
          ),
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
                      widget.existing == null ? 'Add account' : 'Edit account',
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
                PickerField<String>(
                  label: 'Account type',
                  value: _selectedAccountType,
                  options: [
                    for (final type in availableTypes)
                      PickerOption(
                        type,
                        type,
                        leading: Icon(
                          StandardAccountTypes.getIcon(type),
                          size: 18,
                          color: RiveroColors.textSecondary,
                        ),
                      ),
                  ],
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
                      if (parseAmountMinorUnits((v ?? '').trim()) <= 0) {
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
                      if (v == null ||
                          !RegExp(r'^-?\d+(\.\d{0,2})?$').hasMatch(v.trim())) {
                        return 'Enter an amount like 2500 or 2500.50';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: RiveroSpacing.lg),
                Row(
                  children: [
                    BankBadge(
                      name: _institutionController.text.isEmpty
                          ? (_nameController.text.isEmpty
                                ? '?'
                                : _nameController.text)
                          : _institutionController.text,
                      color: _color == null ? null : Color(_color!),
                      imagePath: _imagePath,
                      size: 48,
                    ),
                    const SizedBox(width: RiveroSpacing.md),
                    TextButton.icon(
                      key: const ValueKey('account-photo'),
                      onPressed: () async {
                        final path = await pickPhoto(context);
                        if (path != null) {
                          setState(() {
                            _imagePath = path;
                            _imageChanged = true;
                          });
                        }
                      },
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(
                        _imagePath == null ? 'Add picture' : 'Change',
                      ),
                    ),
                    if (_imagePath != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _imagePath = null;
                          _imageChanged = true;
                        }),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.lg),
                Text('Colour', style: RiveroTypography.bodyMedium),
                const SizedBox(height: RiveroSpacing.sm),
                Wrap(
                  spacing: RiveroSpacing.sm,
                  runSpacing: RiveroSpacing.sm,
                  children: [
                    for (final c in RiveroColors.categorical)
                      GestureDetector(
                        key: ValueKey('account-color-${c.toARGB32()}'),
                        onTap: () => setState(() => _color = c.toARGB32()),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              width: 3,
                              color: _color == c.toARGB32()
                                  ? RiveroColors.textPrimary
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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
                      widget.existing == null ? 'Add account' : 'Save changes',
                      style: RiveroTypography.titleMedium.copyWith(
                        color: RiveroColors.background,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (widget.existing != null)
                  Center(
                    child: TextButton(
                      onPressed: _remove,
                      child: const Text(
                        'Remove account',
                        style: TextStyle(color: RiveroColors.danger),
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
