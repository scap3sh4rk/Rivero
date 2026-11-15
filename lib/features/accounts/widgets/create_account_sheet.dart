import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/currency/currency.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_group.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/storage/media_store.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/color_swatch_picker.dart';
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
  int? _statementDay; // cards: day the statement is generated
  int? _dueDay; // cards: day the bill is due
  String? _billsFrom; // cards: account the bills are paid from
  String _currency = homeCurrency; // bank/cash accounts only
  bool _inNetWorth = true;
  // Fixed deposits: yearly rate (%), opened on, matures on.
  final _rateController = TextEditingController();
  DateTime? _fdStart;
  DateTime? _fdMaturity;

  bool get _isFd =>
      !_isLiability &&
      (_selectedAccountType.toLowerCase().contains('fixed deposit') ||
          _selectedAccountType.toLowerCase().contains('recurring deposit'));

  /// "7.25" -> 725 basis points (two decimals, no floating point).
  int? get _rateBps {
    final t = _rateController.text.trim();
    if (t.isEmpty) return null;
    final v = parseAmountMinorUnits(t);
    return v > 0 && v <= 5000 ? v : null;
  }

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
      _statementDay = a.statementDay;
      _dueDay = a.paymentDueDay;
      _billsFrom = a.billsPaidFromAccountId;
      _currency = a.currencyCode;
      _inNetWorth = a.includeInNetWorth;
      _fdStart = a.fdStartDate;
      _fdMaturity = a.fdMaturityDate;
      final r = a.fdRateBps;
      if (r != null) {
        _rateController.text =
            '${r ~/ 100}.${(r % 100).toString().padLeft(2, '0')}';
      }
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
    _rateController.dispose();
    super.dispose();
  }

  void _onAccountTypeChanged(String? type) {
    if (type == null) return;
    setState(() {
      final was = _selectedAccountType;
      _selectedAccountType = type;
      bool debt(String t) =>
          t == StandardAccountTypes.creditCard ||
          t == StandardAccountTypes.creditLine ||
          t == StandardAccountTypes.loan ||
          t == StandardAccountTypes.overdraft;
      // A debt type switches "this is a debt" on; going back from one to a
      // bank, wallet or cash type switches it off again.
      if (debt(type)) {
        _isLiability = true;
      } else if (debt(was)) {
        _isLiability = false;
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
        // No digits typed = not known yet (never a made-up '0000').
        accountMask: drift.Value(mask.isNotEmpty ? mask : '••••'),
        accountType: drift.Value(_selectedAccountType),
        balanceMinorUnits: drift.Value(balanceMinorUnits),
        // A balance typed here is the truth from this moment (older
        // captures accepted later must not move it again).
        balanceAsOf:
            widget.existing == null ||
                widget.existing!.balanceMinorUnits != balanceMinorUnits
            ? drift.Value(now)
            : const drift.Value.absent(),
        creditLimitMinorUnits: drift.Value(creditLimitMinorUnits),
        isActive: const drift.Value(true),
        isLiability: drift.Value(_isLiability),
        colorValue: drift.Value(_color),
        statementDay: drift.Value(_isLiability ? _statementDay : null),
        paymentDueDay: drift.Value(_isLiability ? _dueDay : null),
        billsPaidFromAccountId: drift.Value(_isLiability ? _billsFrom : null),
        // Cards stay in rupees, so a bill is always compared like for like.
        currencyCode: drift.Value(_isLiability ? homeCurrency : _currency),
        includeInNetWorth: drift.Value(_inNetWorth),
        fdRateBps: drift.Value(_isFd ? _rateBps : null),
        fdStartDate: drift.Value(_isFd ? _fdStart : null),
        fdMaturityDate: drift.Value(_isFd ? _fdMaturity : null),
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

  /// Picks one of the bank pictures the user added (Settings > Bank icons)
  /// for this account.
  Future<void> _pickBankIcon() async {
    final icons = ref.read(bankIconsProvider).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final path = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: RiveroColors.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RiveroSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your bank icons', style: RiveroTypography.titleLarge),
              const SizedBox(height: RiveroSpacing.lg),
              Wrap(
                spacing: RiveroSpacing.lg,
                runSpacing: RiveroSpacing.lg,
                children: [
                  for (final e in icons)
                    InkWell(
                      key: ValueKey('pick-icon-${e.key}'),
                      borderRadius: RiveroRadii.borderLg,
                      onTap: () => Navigator.pop(ctx, e.value),
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            BankBadge(
                              name: e.key,
                              imagePath: e.value,
                              size: 52,
                            ),
                            const SizedBox(height: RiveroSpacing.xs),
                            Text(
                              e.key.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RiveroTypography.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (path == null || !mounted) return;
    setState(() {
      _imagePath = path;
      _imageChanged = true;
    });
  }

  /// Fixed deposit details: rate, opened on, matures on, and what it will
  /// be worth then.
  List<Widget> _fdFields() {
    final f = DateFormat('d MMM y');
    Future<void> pick({required bool start}) async {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        helpText: start ? 'Opened on' : 'Matures on',
        initialDate: start
            ? (_fdStart ?? now)
            : (_fdMaturity ?? DateTime(now.year + 1, now.month, now.day)),
        firstDate: DateTime(now.year - 20),
        lastDate: DateTime(now.year + 30),
      );
      if (d != null) {
        setState(() => start ? _fdStart = d : _fdMaturity = d);
      }
    }

    final principal = parseAmountMinorUnits(_balanceController.text.trim());
    final rate = _rateBps;
    final maturity = rate == null || _fdStart == null || _fdMaturity == null
        ? null
        : FixedDeposit.valueOn(
            principal: principal,
            rateBps: rate,
            start: _fdStart!,
            on: _fdMaturity!,
          );
    return [
      const SizedBox(height: RiveroSpacing.md),
      TextFormField(
        key: const ValueKey('fd-rate'),
        controller: _rateController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Interest rate (% a year)',
          hintText: '7.25',
          suffixText: '%',
        ),
        validator: (v) => (v ?? '').trim().isNotEmpty && _rateBps == null
            ? 'Enter a rate like 7.25'
            : null,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: RiveroSpacing.sm),
      Row(
        children: [
          Expanded(
            child: ListTile(
              key: const ValueKey('fd-start'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Opened on'),
              subtitle: Text(_fdStart == null ? 'Pick' : f.format(_fdStart!)),
              onTap: () => pick(start: true),
            ),
          ),
          Expanded(
            child: ListTile(
              key: const ValueKey('fd-maturity'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Matures on'),
              subtitle: Text(
                _fdMaturity == null ? 'Pick' : f.format(_fdMaturity!),
              ),
              onTap: () => pick(start: false),
            ),
          ),
        ],
      ),
      if (maturity != null)
        Text(
          'At maturity: ${formatIn(maturity, _currency)} '
          '(interest added every quarter)',
          key: const ValueKey('fd-preview'),
          style: RiveroTypography.bodySmall.copyWith(
            color: RiveroColors.success,
          ),
        ),
    ];
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
        // Own ink layer, so list tiles and switches show their splashes.
        child: Material(
          type: MaterialType.transparency,
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
                        widget.existing == null
                            ? 'Add account'
                            : 'Edit account',
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

                  // Account type picker, with a small link to add your own type.
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: _promptNewCustomType,
                      child: Text(
                        '+ Custom type',
                        style: RiveroTypography.labelSmall.copyWith(
                          color: RiveroColors.salaryAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: RiveroSpacing.sm),
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
                    Text(
                      'Credit Limit (₹)',
                      style: RiveroTypography.labelSmall,
                    ),
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
                        helperText: 'Track 10% safe limit and 30% score impact threshold',
                      ),
                      validator: (v) {
                        if (parseAmountMinorUnits((v ?? '').trim()) <= 0) {
                          return 'Please enter a valid credit limit';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: RiveroSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: PickerField<int>(
                            key: const ValueKey('statement-day'),
                            label: 'Statement on',
                            value: _statementDay,
                            options: [
                              for (var d = 1; d <= 31; d++)
                                PickerOption(d, 'Day $d'),
                            ],
                            onChanged: (v) => setState(() => _statementDay = v),
                          ),
                        ),
                        const SizedBox(width: RiveroSpacing.md),
                        Expanded(
                          child: PickerField<int>(
                            key: const ValueKey('due-day'),
                            label: 'Payment due on',
                            value: _dueDay,
                            options: [
                              for (var d = 1; d <= 31; d++)
                                PickerOption(d, 'Day $d'),
                            ],
                            onChanged: (v) => setState(() => _dueDay = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: RiveroSpacing.xs),
                    Text(
                      'Each card has its own billing cycle',
                      style: RiveroTypography.bodySmall,
                    ),
                    const SizedBox(height: RiveroSpacing.md),
                    PickerField<String>(
                      key: const ValueKey('bills-paid-from'),
                      label: 'Bills paid from',
                      value: _billsFrom ?? '',
                      options: [
                        const PickerOption('', 'My spending money'),
                        for (final a
                            in ref
                                    .watch(activePhysicalAccountsProvider)
                                    .value ??
                                const <PhysicalAccount>[])
                          if (!a.isLiability && a.id != widget.existing?.id)
                            PickerOption(a.id, a.name),
                      ],
                      onChanged: (v) =>
                          setState(() => _billsFrom = v.isEmpty ? null : v),
                    ),
                    const SizedBox(height: RiveroSpacing.xs),
                    Text(
                      'Keep card money in its own account? Pick it: what it '
                      'holds is set aside for the bill, so Safe to spend only '
                      'counts the rest.',
                      style: RiveroTypography.bodySmall,
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
                    PickerField<String>(
                      key: const ValueKey('account-currency'),
                      label: 'Currency',
                      value: _currency,
                      options: [
                        for (final c in currencySymbols.keys)
                          PickerOption(c, c),
                      ],
                      onChanged: (v) => setState(() => _currency = v),
                    ),
                    const SizedBox(height: RiveroSpacing.md),
                    Text(
                      _isFd
                          ? 'Amount deposited ($_currency)'
                          : 'Initial Balance ($_currency)',
                      style: RiveroTypography.labelSmall,
                    ),
                    const SizedBox(height: RiveroSpacing.xs),
                    TextFormField(
                      controller: _balanceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: RiveroTypography.bodyLarge,
                      decoration: InputDecoration(
                        prefixText: '${currencySymbols[_currency]!.trim()} ',
                        hintText: '50000.00',
                      ),
                      validator: (v) {
                        if (v == null ||
                            !RegExp(r'^-?\d+(\.\d{0,2})?$')
                                .hasMatch(v.trim())) {
                          return 'Enter an amount like 2500 or 2500.50';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_isFd) ..._fdFields(),
                  ],
                  const SizedBox(height: RiveroSpacing.md),
                  SwitchListTile(
                    key: const ValueKey('in-net-worth'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Count in net worth'),
                    subtitle: const Text(
                      'Off: still listed, but left out of the net worth total',
                    ),
                    value: _inNetWorth,
                    onChanged: (v) => setState(() => _inNetWorth = v),
                  ),
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
                  // Pictures already added in Settings > Bank icons.
                  if (ref.watch(bankIconsProvider).isNotEmpty)
                    TextButton.icon(
                      key: const ValueKey('account-bank-icon'),
                      onPressed: _pickBankIcon,
                      icon: const Icon(Icons.collections_outlined),
                      label: const Text('Choose from your bank icons'),
                    ),
                  const SizedBox(height: RiveroSpacing.lg),
                  Text('Colour', style: RiveroTypography.bodyMedium),
                  const SizedBox(height: RiveroSpacing.sm),
                  ColorSwatchPicker(
                    keyPrefix: 'account-color',
                    selected: _color,
                    onPick: (c) => setState(() => _color = c),
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
                        widget.existing == null
                            ? 'Add account'
                            : 'Save changes',
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
      ),
    );
  }
}
