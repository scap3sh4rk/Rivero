import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
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
  String _category = 'Food';
  String? _accountId;

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

  PhysicalAccount? _account(List<PhysicalAccount> accounts) {
    final spendable = accounts.where((a) => !a.isLiability).toList();
    final pool = accounts.where((a) => a.id == _accountId);
    if (pool.isNotEmpty) return pool.first;
    return spendable.firstOrNull ?? accounts.firstOrNull;
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
        );
    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    setState(() => _text = '');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${_income ? 'Income' : 'Expense'} saved'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(activePhysicalAccountsProvider).value ?? [];
    final account = _account(accounts);
    final privacy = ref.watch(privacyModeProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: const RiveroAppBar(title: 'Log'),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: RiveroSpacing.lg,
                ),
                children: [
                  for (final c in _categories)
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
                child: Text(
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
            if (accounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: RiveroSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('Income'),
                      selected: _income,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      onSelected: (v) => setState(() => _income = v),
                    ),
                    const SizedBox(width: RiveroSpacing.sm),
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
