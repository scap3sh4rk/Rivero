import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/picker.dart';

/// Adds a bank message Rivero could not read, right on Home: the amount it
/// found (editable), money in or out, the account, a category (required)
/// and an optional description. The message itself is never the note.
class AddFromMessageSheet extends ConsumerStatefulWidget {
  const AddFromMessageSheet({
    required this.message,
    required this.prefill,
    super.key,
  });

  final String message;
  final LogPrefill prefill;

  /// Returns true when the payment was added.
  static Future<bool> show(
    BuildContext context, {
    required String message,
    required LogPrefill prefill,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: RiveroColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => AddFromMessageSheet(message: message, prefill: prefill),
      ) ??
      false;

  @override
  ConsumerState<AddFromMessageSheet> createState() =>
      _AddFromMessageSheetState();
}

class _AddFromMessageSheetState extends ConsumerState<AddFromMessageSheet> {
  late final _amount = TextEditingController(text: widget.prefill.amountText);
  late final _note = TextEditingController(text: widget.prefill.note);
  late bool _income = widget.prefill.income;
  late String? _category = widget.prefill.category;
  String? _accountId;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The account the message names by its last digits, else the last one
  /// logged to, else the first bank account.
  PhysicalAccount? _guess(List<PhysicalAccount> all) {
    final digits = RegExp(r'\d{4}').allMatches(widget.message).map((m) {
      return m.group(0)!;
    }).toSet();
    return all
            .where(
              (a) =>
                  RegExp(r'^\d{3,6}$').hasMatch(a.accountMask.trim()) &&
                  digits.any((d) => d.endsWith(a.accountMask.trim())),
            )
            .firstOrNull ??
        all
            .where((a) => a.id == ref.read(lastLogAccountProvider))
            .firstOrNull ??
        all.where((a) => !a.isLiability).firstOrNull ??
        all.firstOrNull;
  }

  Future<void> _add(PhysicalAccount account) async {
    final minor = parseAmountMinorUnits(_amount.text);
    if (_busy || minor <= 0 || (!_income && _category == null)) return;
    setState(() => _busy = true);
    final category = _income ? (_category ?? 'Income') : _category!;
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
          note: note.isEmpty ? null : note,
        );
    unawaited(HapticFeedback.lightImpact());
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(activePhysicalAccountsProvider).value ?? [];
    final account =
        accounts.where((a) => a.id == _accountId).firstOrNull ??
        _guess(accounts);
    final categories = ref.watch(logCategoriesProvider).map((c) => c.name);
    final minor = parseAmountMinorUnits(_amount.text);
    final ready =
        account != null && minor > 0 && (_income || _category != null);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        RiveroSpacing.xl,
        RiveroSpacing.xl,
        RiveroSpacing.xl,
        MediaQuery.viewInsetsOf(context).bottom + RiveroSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: RiveroTypography.bodySmall,
            ),
            const SizedBox(height: RiveroSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('msg-amount'),
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    style: RiveroTypography.financialMedium,
                    decoration: const InputDecoration(prefixText: '₹'),
                  ),
                ),
                const SizedBox(width: RiveroSpacing.sm),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Spent')),
                    ButtonSegment(value: true, label: Text('Received')),
                  ],
                  selected: {_income},
                  onSelectionChanged: (s) => setState(() => _income = s.first),
                ),
              ],
            ),
            const SizedBox(height: RiveroSpacing.md),
            if (accounts.isNotEmpty)
              PickerField<String>(
                key: const ValueKey('msg-account'),
                label: _income ? 'Received in' : 'Paid from',
                value: account?.id,
                options: [for (final a in accounts) PickerOption(a.id, a.name)],
                onChanged: (v) => setState(() => _accountId = v),
              ),
            if (!_income) ...[
              const SizedBox(height: RiveroSpacing.md),
              Text(
                _category == null ? 'Pick a category' : 'Category',
                style: RiveroTypography.bodySmall.copyWith(
                  color: _category == null ? RiveroColors.warning : null,
                ),
              ),
              const SizedBox(height: RiveroSpacing.xs),
              Wrap(
                spacing: RiveroSpacing.sm,
                runSpacing: RiveroSpacing.xs,
                children: [
                  for (final c in categories)
                    ChoiceChip(
                      key: ValueKey('msg-cat-$c'),
                      label: Text(c),
                      selected: _category == c,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      onSelected: (on) =>
                          setState(() => _category = on ? c : null),
                    ),
                ],
              ),
            ],
            const SizedBox(height: RiveroSpacing.md),
            TextField(
              key: const ValueKey('msg-note'),
              controller: _note,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Description (optional)',
                counterText: '',
              ),
            ),
            const SizedBox(height: RiveroSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                key: const ValueKey('msg-add'),
                onPressed: ready && !_busy ? () => _add(account) : null,
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                child: Text(
                  !_income && _category == null ? 'Pick a category' : 'Add',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
