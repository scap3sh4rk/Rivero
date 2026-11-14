import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/calc.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/account_color.dart';
import 'package:rivero/design_system/widgets/picker.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/features/log/scan_bill.dart';
import 'package:rivero/features/settings/screens/categories_screen.dart';

/// Quick log: what it was for (optional), an amount, Save. Category and
/// account are one tap each; nothing is pre-selected that you did not pick.
class QuickLogScreen extends ConsumerStatefulWidget {
  const QuickLogScreen({super.key});

  @override
  ConsumerState<QuickLogScreen> createState() => _QuickLogScreenState();
}

class _QuickLogScreenState extends ConsumerState<QuickLogScreen> {
  static const _ops = '+-×÷';
  static const _maxExpression = 24;

  String _text = '';
  bool _income = false;
  bool _calcOpen = false;
  String? _category; // none until the user (or a remembered note) picks one
  late String? _accountId = ref.read(lastLogAccountProvider);
  String? _savedLabel;
  Timer? _savedTimer;
  final _note = TextEditingController();
  final _noteFocus = FocusNode();

  @override
  void dispose() {
    _savedTimer?.cancel();
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  // ---- amount / calculator -------------------------------------------------

  /// Amount to save: the evaluated expression (a trailing operator ignored).
  int get _amount {
    var e = _text;
    while (e.isNotEmpty && _ops.contains(e[e.length - 1])) {
      e = e.substring(0, e.length - 1);
    }
    return e.isEmpty ? 0 : (evaluateExpression(e) ?? 0);
  }

  void _key(String k) {
    HapticFeedback.selectionClick();
    _noteFocus.unfocus(); // amounts come from the keypad, not the keyboard
    final lastOp = _text.lastIndexOf(RegExp('[+×÷-]'));
    final current = _text.substring(lastOp + 1);
    final endsWithOp =
        _text.isNotEmpty && _ops.contains(_text[_text.length - 1]);
    setState(() {
      if (k == 'calc') {
        _calcOpen = !_calcOpen;
      } else if (k == 'clear') {
        _text = '';
      } else if (k == '<') {
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
      } else if (k == '=') {
        final v = _amount;
        _text = v <= 0 ? '' : _formatPaise(v);
      } else if (_ops.contains(k)) {
        if (_text.isEmpty) return;
        _text = endsWithOp
            ? '${_text.substring(0, _text.length - 1)}$k'
            : '$_text$k';
      } else if (k == '%') {
        if (current.isNotEmpty && !current.contains('%') && !endsWithOp) {
          _text = '$_text%';
        }
      } else if (_text.length >= _maxExpression || current.contains('%')) {
        return;
      } else if (k == '.') {
        if (!current.contains('.')) {
          _text = current.isEmpty ? '${_text}0.' : '$_text.';
        }
      } else {
        final dot = current.indexOf('.');
        if (dot != -1 && current.length - dot > 2) return; // 2 decimals
        _text = _text == '0' ? k : '$_text$k';
      }
    });
  }

  // ---- categories ------------------------------------------------------------

  /// Typing a note you have used before brings back its category.
  void _learnCategory(String note, List<LedgerTransaction> txns) {
    final key = note.trim().toLowerCase();
    if (key.length < 2) return;
    final match = txns
        .where((t) => t.amountMinorUnits < 0 && t.merchant.toLowerCase() == key)
        .firstOrNull;
    if (match != null && match.category != _category) {
      setState(() => _category = match.category);
    }
  }

  /// Most-used categories first (last 90 days), then the user's order.
  static List<String> _orderedCategories(
    List<LedgerTransaction> txns,
    List<String> known,
  ) {
    final since = DateTime.now().subtract(const Duration(days: 90));
    final counts = <String, int>{};
    for (final t in txns) {
      if (t.amountMinorUnits < 0 &&
          !t.isInternalTransfer &&
          t.transactionTimestamp.isAfter(since)) {
        counts[t.category] = (counts[t.category] ?? 0) + 1;
      }
    }
    final base = {for (var i = 0; i < known.length; i++) known[i]: i};
    return known.toList()..sort((a, b) {
      final c = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
      return c != 0 ? c : (base[a] ?? 99).compareTo(base[b] ?? 99);
    });
  }

  // ---- accounts --------------------------------------------------------------

  /// Chosen account, else the one spending draws from, else the first bank.
  PhysicalAccount? _account(
    List<PhysicalAccount> accounts,
    List<AllocationBucket> buckets,
  ) {
    PhysicalAccount? byId(String? id) =>
        accounts.where((a) => a.id == id).firstOrNull;
    final spendingAccount = buckets
        .where((b) => b.role == AccountRole.expense)
        .firstOrNull
        ?.linkedPhysicalAccountId;
    final expenseNamed = accounts
        .where(
          (a) =>
              !a.isLiability &&
              (a.accountType == 'Daily Expense' ||
                  a.name.toLowerCase().contains('expen') ||
                  a.name.toLowerCase().contains('spend')),
        )
        .firstOrNull;
    return byId(_accountId) ??
        expenseNamed ??
        byId(spendingAccount) ??
        accounts.where((a) => !a.isLiability).firstOrNull ??
        accounts.firstOrNull;
  }

  /// Asks before logging a spend bigger than the account holds or than the
  /// spending budget left. Returns true to go ahead.
  Future<bool> _confirmLargeSpend(PhysicalAccount account, int minor) async {
    if (_income) return true;
    final b = ref.read(stsBreakdownProvider).value;
    final reasons = <String>[];
    if (!account.isLiability &&
        account.balanceMinorUnits > 0 &&
        minor > account.balanceMinorUnits) {
      final held = CurrencyFormatter.format(account.balanceMinorUnits);
      reasons.add('more than the $held in ${account.name}');
    }
    if (b != null && b.planned + b.carriedOver > 0 && minor > b.budgetLeft) {
      if (b.budgetLeft > 0) {
        final left = CurrencyFormatter.format(b.budgetLeft);
        reasons.add('more than the $left left in your spending budget');
      } else {
        reasons.add('on top of a spending budget that is already used up');
      }
    }
    if (reasons.isEmpty) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log this anyway?'),
        content: Text(
          '${CurrencyFormatter.format(minor)} is ${reasons.join(' and ')}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('log-anyway'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log anyway'),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  Future<void> _save(PhysicalAccount account) async {
    final minor = _amount;
    if (minor == 0) return;
    if (!await _confirmLargeSpend(account, minor)) return;
    final category = _income ? 'Income' : (_category ?? 'Other');
    final note = _note.text.trim();
    await ref
        .read(ledgerServiceProvider)
        .recordManual(
          accountId: account.id,
          amountMinorUnits: _income ? minor : -minor,
          type: _income
              ? TransactionType.income
              : account.isLiability
              ? TransactionType.creditCardPurchase
              : TransactionType.expense,
          merchant: note.isEmpty ? category : note,
          category: category,
        );
    ref.read(lastLogAccountProvider.notifier).state = account.id;
    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    // Inline confirmation: a snackbar would sit on top of the Save button.
    setState(() {
      _text = '';
      _note.clear();
      _category = null;
      _calcOpen = false;
      _savedLabel = _income ? 'Income saved' : 'Saved to $category';
    });
    _savedTimer?.cancel();
    _savedTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _savedLabel = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(activePhysicalAccountsProvider).value ?? [];
    final buckets = ref.watch(allAllocationBucketsProvider).value ?? const [];
    final account = _account(accounts, buckets);
    final privacy = ref.watch(privacyModeProvider);
    final txns = ref.watch(allTransactionsStreamProvider).value ?? const [];
    final categories = _orderedCategories(txns, [
      ...{...ref.watch(logCategoriesProvider).map((c) => c.name), ?_category},
    ]);
    final accountTint = account == null ? null : accountColor(account);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Log',
        actions: [
          IconButton(
            key: const ValueKey('scan-bill'),
            tooltip: 'Scan a bill (experimental)',
            onPressed: () => scanBill(context, ref),
            icon: const Icon(Icons.document_scanner_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.lg),
              child: TextField(
                key: const ValueKey('log-note'),
                controller: _note,
                focusNode: _noteFocus,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                maxLength: 80,
                onChanged: (v) => _learnCategory(v, txns),
                decoration: const InputDecoration(
                  hintText: 'What was it for?',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: RiveroRadii.borderFull,
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: RiveroRadii.borderFull,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (!_income) ...[
              const SizedBox(height: RiveroSpacing.sm),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: RiveroSpacing.lg,
                  ),
                  children: [
                    for (final c in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: RiveroSpacing.sm),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          showCheckmark: false,
                          shape: const StadiumBorder(),
                          // Tap again to clear.
                          onSelected: (on) =>
                              setState(() => _category = on ? c : null),
                        ),
                      ),
                    ActionChip(
                      key: const ValueKey('new-category'),
                      avatar: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('New'),
                      shape: const StadiumBorder(),
                      onPressed: () async {
                        final name = await promptNewCategory(context, ref);
                        if (name != null) setState(() => _category = name);
                      },
                    ),
                  ],
                ),
              ),
            ],
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _savedLabel != null && _text.isEmpty
                      ? Row(
                          key: const ValueKey('saved'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: RiveroColors.success,
                            ),
                            const SizedBox(width: RiveroSpacing.sm),
                            Text(
                              _savedLabel!,
                              style: RiveroTypography.titleLarge,
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isCalculation(_text))
                              Text(
                                _text.replaceAll('-', '−'),
                                key: const ValueKey('expression'),
                                style: RiveroTypography.titleLarge.copyWith(
                                  color: RiveroColors.textSecondary,
                                ),
                              ),
                            if (isAmountTooLarge(_text))
                              Text(
                                'Amount too large',
                                key: const ValueKey('too-large'),
                                style: RiveroTypography.bodySmall.copyWith(
                                  color: RiveroColors.danger,
                                ),
                              ),
                            FittedBox(
                              child: Text(
                                privacy && _text.isNotEmpty
                                    ? '₹••••'
                                    : '${_income ? '+' : ''}₹'
                                          '${isCalculation(_text) ? _formatPaise(_amount) : (_text.isEmpty ? '0' : _text)}',
                                key: const ValueKey('amount'),
                                style: RiveroTypography.financialHero.copyWith(
                                  fontSize: 64,
                                  color: _income
                                      ? RiveroColors.success
                                      : RiveroColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            if (accounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RiveroSpacing.lg,
                  0,
                  RiveroSpacing.lg,
                  RiveroSpacing.sm,
                ),
                // Equal, fixed-width pills: a long account name is cut
                // cleanly and never changes the row's layout.
                child: Row(
                  children: [
                    Expanded(
                      child: _Pill(
                        key: const ValueKey('income-pill'),
                        icon: Icons.south_west_rounded,
                        label: 'Income',
                        active: _income,
                        onTap: () => setState(() => _income = !_income),
                      ),
                    ),
                    const SizedBox(width: RiveroSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: _Pill(
                        key: const ValueKey('account-chip'),
                        dot: accountTint,
                        label: account?.name ?? 'Account',
                        active: true,
                        tint: accountTint,
                        onTap: () async {
                          final picked = await showPicker<String>(
                            context,
                            title: _income ? 'Received in' : 'Paid from',
                            selected: account?.id,
                            options: [
                              for (final a in accounts)
                                PickerOption(
                                  a.id,
                                  a.name,
                                  leading: ColorDot(accountColor(a)),
                                ),
                            ],
                          );
                          if (picked != null) {
                            setState(() => _accountId = picked.value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Keypad(onKey: _key, calcOpen: _calcOpen),
                ),
                // Operator pane slides in from the right edge; the keypad
                // narrows instead of being covered.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: _calcOpen ? 72 : 0,
                  height: 256,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: RiveroColors.surfaceElevated,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(20),
                    ),
                  ),
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 72,
                    maxWidth: 72,
                    child: Column(
                      children: [
                        for (final op in ['÷', '×', '-', '+', '%', '.', '='])
                          Expanded(
                            child: InkResponse(
                              key: ValueKey('op-$op'),
                              radius: 22,
                              splashFactory: InkRipple.splashFactory,
                              onTap: () => _key(op),
                              child: Center(
                                child: Text(
                                  op == '-' ? '−' : op,
                                  style: RiveroTypography.displayMedium,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(RiveroSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: account == null || _amount <= 0
                      ? null
                      : () => _save(account),
                  child: const Text('Save'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey, required this.calcOpen});

  final void Function(String) onKey;
  final bool calcOpen;

  @override
  Widget build(BuildContext context) {
    // The decimal point is rare when logging: it lives in the calculator
    // pane, or long-press 0.
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['calc', '0', '<'],
    ];
    return Column(
      children: [
        for (final row in rows)
          Row(
            children: [
              for (final k in row)
                Expanded(
                  child: InkResponse(
                    key: ValueKey(k == 'calc' ? 'calc-toggle' : 'key-$k'),
                    // Soft ripple from behind the digit, sized to the digit.
                    radius: 32,
                    splashFactory: InkRipple.splashFactory,
                    onTap: () => onKey(k),
                    onLongPress: switch (k) {
                      '<' => () => onKey('clear'),
                      '0' => () => onKey('.'),
                      _ => null,
                    },
                    child: SizedBox(
                      height: 64,
                      child: Center(
                        child: switch (k) {
                          '<' => const Icon(Icons.backspace_outlined, size: 22),
                          'calc' => Icon(
                            calcOpen
                                ? Icons.calculate_rounded
                                : Icons.calculate_outlined,
                            size: 24,
                            color: calcOpen
                                ? RiveroColors.accent
                                : RiveroColors.textSecondary,
                          ),
                          _ => Text(
                            k,
                            style: RiveroTypography.displayLarge.copyWith(
                              fontSize: 26,
                            ),
                          ),
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

String _formatPaise(int v) {
  final sign = v < 0 ? '-' : '';
  final a = v.abs();
  return a % 100 == 0
      ? '$sign${a ~/ 100}'
      : '$sign${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
}

/// Fixed-height pill used in the Log bottom row.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
    this.icon,
    this.dot,
    this.tint,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? RiveroColors.accent;
    return Material(
      color: active
          ? color.withValues(alpha: 0.14)
          : RiveroColors.surfaceElevated,
      shape: StadiumBorder(
        side: BorderSide(
          color: active ? color.withValues(alpha: 0.6) : Colors.transparent,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (dot != null) ColorDot(dot!),
                if (icon != null)
                  Icon(
                    icon,
                    size: 16,
                    color: active ? color : RiveroColors.textSecondary,
                  ),
                const SizedBox(width: RiveroSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RiveroTypography.labelLarge,
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
