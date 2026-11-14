import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/calc.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/account_color.dart';
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
  String? _bucketId; // null = spending; else a set-aside category (e.g. Rent)
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
    return byId(_accountId) ??
        byId(spendingAccount) ??
        accounts.where((a) => !a.isLiability).firstOrNull ??
        accounts.firstOrNull;
  }

  Future<void> _save(PhysicalAccount account) async {
    final minor = _amount;
    if (minor == 0) return;
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
          bucketId: _income ? null : _bucketId,
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
    final payFrom = buckets.where((b) => b.role == AccountRole.custom).toList();
    final payFromName = buckets
        .where((b) => b.id == _bucketId)
        .firstOrNull
        ?.name;
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
                padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: RiveroSpacing.sm,
                  runSpacing: RiveroSpacing.xs,
                  children: [
                    FilterChip(
                      label: const Text('Income'),
                      selected: _income,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      onSelected: (v) => setState(() => _income = v),
                    ),
                    PopupMenuButton<String>(
                      key: const ValueKey('account-chip'),
                      onSelected: (id) => setState(() => _accountId = id),
                      itemBuilder: (_) => [
                        for (final a in accounts)
                          PopupMenuItem(
                            value: a.id,
                            child: Row(
                              children: [
                                ColorDot(accountColor(a)),
                                const SizedBox(width: RiveroSpacing.sm),
                                Text(a.name),
                              ],
                            ),
                          ),
                      ],
                      // The account's own colour makes the choice obvious.
                      child: Chip(
                        avatar: accountTint == null
                            ? null
                            : ColorDot(accountTint),
                        label: Text('${account?.name}'),
                        side: accountTint == null
                            ? null
                            : BorderSide(
                                color: accountTint.withValues(alpha: 0.7),
                              ),
                        backgroundColor: accountTint?.withValues(alpha: 0.14),
                        shape: const StadiumBorder(),
                      ),
                    ),
                    if (payFrom.isNotEmpty && !_income)
                      PopupMenuButton<String>(
                        key: const ValueKey('pay-from'),
                        onSelected: (id) =>
                            setState(() => _bucketId = id.isEmpty ? null : id),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: '',
                            child: Text('Spending'),
                          ),
                          for (final b in payFrom)
                            PopupMenuItem(value: b.id, child: Text(b.name)),
                        ],
                        child: Chip(
                          avatar: const Icon(
                            Icons.call_split_rounded,
                            size: 16,
                          ),
                          label: Text(payFromName ?? 'Spending'),
                          shape: const StadiumBorder(),
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
