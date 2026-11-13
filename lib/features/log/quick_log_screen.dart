import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';

/// Lowest-friction logging: type an amount, tap a category, save.
/// Account defaults to the first spending account; everything else is optional.
class QuickLogScreen extends ConsumerStatefulWidget {
  const QuickLogScreen({super.key});

  @override
  ConsumerState<QuickLogScreen> createState() => _QuickLogScreenState();
}

class _QuickLogScreenState extends ConsumerState<QuickLogScreen> {
  static const _categories = [
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Health',
    'Fun',
    'Other',
  ];
  static const _maxLength = 9;

  String _text = '';
  bool _income = false;
  late String _category = ref.read(lastLogCategoryProvider);
  late String? _accountId = ref.read(lastLogAccountProvider);

  /// null = the spending bucket; otherwise a set-aside category (e.g. Rent).
  String? _bucketId;

  String? _savedLabel;
  Timer? _savedTimer;

  @override
  void dispose() {
    _savedTimer?.cancel();
    super.dispose();
  }

  void _key(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == 'clear') {
        _text = '';
      } else if (k == '<') {
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
      } else if (k == '.') {
        if (!_text.contains('.')) _text = _text.isEmpty ? '0.' : '$_text.';
      } else if (_text.length < _maxLength) {
        final dot = _text.indexOf('.');
        if (dot != -1 && _text.length - dot > 2) return; // max 2 decimals
        _text = _text == '0' ? k : '$_text$k';
      }
    });
  }

  /// Chosen account, else the one the spending bucket draws from, else the
  /// first non-card account.
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

  /// Last distinct (category, amount) expenses: one tap to log them again.
  static List<LedgerTransaction> _recents(List<LedgerTransaction> txns) {
    final seen = <String>{};
    final out = <LedgerTransaction>[];
    for (final t in txns) {
      if (t.amountMinorUnits >= 0 ||
          t.transactionState != TransactionState.confirmed ||
          t.isInternalTransfer) {
        continue;
      }
      if (seen.add('${t.category}|${t.amountMinorUnits}')) out.add(t);
      if (out.length == 6) break;
    }
    return out;
  }

  void _fillFrom(LedgerTransaction t) {
    final minor = t.amountMinorUnits.abs();
    setState(() {
      _income = false;
      _category = t.category;
      _text = minor % 100 == 0
          ? '${minor ~/ 100}'
          : '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
    });
  }

  Future<void> _save(PhysicalAccount account) async {
    final minor = parseAmountMinorUnits(_text);
    if (minor == 0) return;
    final onCard = account.isLiability;
    await ref
        .read(ledgerServiceProvider)
        .recordManual(
          accountId: account.id,
          amountMinorUnits: _income ? minor : -minor,
          type: _income
              ? TransactionType.income
              : onCard
              ? TransactionType.creditCardPurchase
              : TransactionType.expense,
          merchant: _category,
          category: _category,
          bucketId: _income ? null : _bucketId,
        );
    ref.read(lastLogCategoryProvider.notifier).state = _category;
    ref.read(lastLogAccountProvider.notifier).state = account.id;
    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    // Inline confirmation: a snackbar would sit on top of the Save button.
    setState(() {
      _text = '';
      _savedLabel = _income ? 'Income saved' : 'Saved to $_category';
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
    final recents = _recents(
      ref.watch(allTransactionsStreamProvider).value ?? const [],
    );
    // Categories you can pay from directly (Rent, Family...), besides spending.
    final payFrom = buckets.where((b) => b.role == AccountRole.custom).toList();
    final payFromName = buckets
        .where((b) => b.id == _bucketId)
        .firstOrNull
        ?.name;

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: const RiveroAppBar(title: 'Log'),
      body: SafeArea(
        child: Column(
          children: [
            if (recents.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  key: const ValueKey('recents'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: RiveroSpacing.lg,
                  ),
                  children: [
                    for (final t in recents)
                      Padding(
                        padding: const EdgeInsets.only(right: RiveroSpacing.sm),
                        child: ActionChip(
                          avatar: const Icon(Icons.history_rounded, size: 16),
                          label: Text(
                            privacy
                                ? t.category
                                : '${t.category} '
                                      '${CurrencyFormatter.format(t.amountMinorUnits.abs())}',
                          ),
                          shape: const StadiumBorder(),
                          onPressed: () => _fillFrom(t),
                        ),
                      ),
                  ],
                ),
              ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: RiveroSpacing.lg,
                ),
                children: [
                  for (final c in {..._categories, _category})
                    Padding(
                      padding: const EdgeInsets.only(right: RiveroSpacing.sm),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: _category == c,
                        showCheckmark: false,
                        shape: const StadiumBorder(),
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
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
                      : Text(
                          privacy && _text.isNotEmpty
                              ? '₹••••'
                              : '${_income ? '+' : ''}₹${_text.isEmpty ? '0' : _text}',
                          key: const ValueKey('amount'),
                          style: RiveroTypography.financialHero.copyWith(
                            fontSize: 64,
                            color: _income
                                ? RiveroColors.success
                                : RiveroColors.textPrimary,
                          ),
                        ),
                ),
              ),
            ),
            if (accounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: RiveroSpacing.md),
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
                      onSelected: (id) => setState(() => _accountId = id),
                      itemBuilder: (_) => [
                        for (final a in accounts)
                          PopupMenuItem(value: a.id, child: Text(a.name)),
                      ],
                      child: Chip(
                        avatar: const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 16,
                        ),
                        label: Text('${account?.name}'),
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
            _Keypad(onKey: _key),
            Padding(
              padding: const EdgeInsets.all(RiveroSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    backgroundColor: RiveroColors.textPrimary,
                    foregroundColor: RiveroColors.background,
                  ),
                  onPressed:
                      account == null || parseAmountMinorUnits(_text) == 0
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
  const _Keypad({required this.onKey});

  final void Function(String) onKey;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', '<'],
    ];
    return Column(
      children: [
        for (final row in rows)
          Row(
            children: [
              for (final k in row)
                Expanded(
                  child: InkResponse(
                    key: ValueKey('key-$k'),
                    // Round highlight the size of the digit, not the cell.
                    radius: 30,
                    onTap: () => onKey(k),
                    onLongPress: k == '<' ? () => onKey('clear') : null,
                    child: SizedBox(
                      height: 64,
                      child: Center(
                        child: k == '<'
                            ? const Icon(Icons.backspace_outlined, size: 22)
                            : Text(
                                k,
                                style: RiveroTypography.displayLarge.copyWith(
                                  fontSize: 26,
                                ),
                              ),
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
