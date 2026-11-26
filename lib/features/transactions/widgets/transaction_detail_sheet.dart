import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/storage/media_store.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/account_color.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/photo_picker.dart';
import 'package:rivero/design_system/widgets/picker.dart';
import 'package:rivero/features/settings/screens/categories_screen.dart';
import 'package:rivero/features/transactions/widgets/split_sheet.dart';
import 'package:rivero/features/transactions/widgets/undo.dart';

/// One transaction: what it was, a note, its category, and fixes
/// (confirm / ignore / delete). Opened by tapping a row in Activity.
class TransactionDetailSheet extends ConsumerStatefulWidget {
  const TransactionDetailSheet({required this.transaction, super.key});

  final LedgerTransaction transaction;

  static Future<void> show(BuildContext context, LedgerTransaction t) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RiveroColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => TransactionDetailSheet(transaction: t),
    );
  }

  @override
  ConsumerState<TransactionDetailSheet> createState() =>
      _TransactionDetailSheetState();
}

class _TransactionDetailSheetState
    extends ConsumerState<TransactionDetailSheet> {
  late final _note = TextEditingController(
    text: widget.transaction.userNotes ?? '',
  );
  late String _category = widget.transaction.category;
  late String? _bill = widget.transaction.attachmentPath;
  late String _accountId = widget.transaction.physicalAccountId;

  /// The entry as it is now (amount, date and name can be corrected here).
  late LedgerTransaction _t = widget.transaction;

  /// Corrects the amount, date or name; balances and budget follow.
  Future<void> _edit() async {
    final t = _t;
    final r = await showDialog<({int amount, String name, DateTime when})>(
      context: context,
      builder: (_) => _EditEntryDialog(entry: t),
    );
    if (r == null) return;
    await ref
        .read(ledgerServiceProvider)
        .edit(
          t.id,
          amountMinorUnits: r.amount,
          timestamp: r.when,
          merchant: r.name,
        );
    final fresh = await _db.transactionsDao.getTransactionById(t.id);
    if (fresh != null && mounted) setState(() => _t = fresh);
  }

  /// The payment came from (or landed in) another account: move it there.
  Future<void> _pickAccount(
    BuildContext anchor,
    List<PhysicalAccount> accounts,
  ) async {
    final picked = await showDropdown<String>(
      anchor,
      options: [
        for (final a in accounts)
          PickerOption(a.id, a.name, leading: ColorDot(accountColor(a))),
      ],
      selected: _accountId,
    );
    if (picked == null || picked.value == _accountId) return;
    await ref
        .read(ledgerServiceProvider)
        .changeAccount(widget.transaction.id, picked.value);
    if (mounted) setState(() => _accountId = picked.value);
  }

  Future<void> _attachBill() async {
    final picked = await pickPhoto(context);
    if (picked == null) return;
    final t = widget.transaction;
    final stored = await MediaStore.keep(
      picked,
      folder: MediaStore.bills,
      name: t.id,
    );
    await MediaStore.remove(_bill);
    await _db.transactionsDao.updateAttachment(t.id, stored);
    if (mounted) setState(() => _bill = stored);
  }

  Future<void> _removeBill() async {
    await MediaStore.remove(_bill);
    await _db.transactionsDao.updateAttachment(widget.transaction.id, null);
    if (mounted) setState(() => _bill = null);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  RiveroDatabase get _db => ref.read(databaseProvider);

  Future<void> _saveAndClose() async {
    final t = widget.transaction;
    if (_note.text.trim() != (t.userNotes ?? '')) {
      await _db.transactionsDao.updateTransactionNote(t.id, _note.text);
    }
    if (_category != t.category) {
      await _db.transactionsDao.updateTransactionCategory(
        t.id,
        category: _category,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  /// Deletes with Undo (see deleteWithUndo): no "are you sure" first.
  void _delete() {
    deleteWithUndo(context, widget.transaction.id);
    Navigator.pop(context);
  }

  Future<void> _confirm() async {
    await ref.read(ledgerServiceProvider).confirm(widget.transaction.id);
    await ref.read(reconciliationServiceProvider).reconcileAll();
    await _saveAndClose();
  }

  Future<void> _ignore() async {
    await ignoreWithUndo(context, widget.transaction.id);
    await _saveAndClose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final privacy = ref.watch(privacyModeProvider);
    final accounts =
        ref.watch(activePhysicalAccountsProvider).value ?? const [];
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    // A transfer is a pair of legs: its accounts are not edited one by one.
    final canMove =
        !t.isInternalTransfer &&
        t.linkedTransactionId == null &&
        accounts.length > 1;
    final pending = t.transactionState == TransactionState.needsReview;
    final credit = t.amountMinorUnits > 0;
    final cats = {
      ...ref.watch(logCategoriesProvider).map((c) => c.name),
      t.category,
      _category,
    }.toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        RiveroSpacing.xl,
        RiveroSpacing.lg,
        RiveroSpacing.xl,
        MediaQuery.viewInsetsOf(context).bottom + RiveroSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: RiveroColors.surfaceInteractive,
                  borderRadius: RiveroRadii.borderFull,
                ),
              ),
            ),
            const SizedBox(height: RiveroSpacing.lg),
            // The amount on the left; the bank it moved through on the
            // right, its icon with the bank's name under it.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    privacy
                        ? '₹••••'
                        : '${credit ? '+' : ''}'
                              '${CurrencyFormatter.format(t.amountMinorUnits.abs())}',
                    style: RiveroTypography.financialLarge.copyWith(
                      color: credit ? RiveroColors.success : null,
                    ),
                  ),
                ),
                if (account != null)
                  Builder(
                    builder: (anchor) => InkWell(
                      key: const ValueKey('detail-account'),
                      borderRadius: RiveroRadii.borderMd,
                      onTap: canMove
                          ? () => _pickAccount(anchor, accounts)
                          : null,
                      child: Column(
                        children: [
                          BankBadge(
                            name: account.institution,
                            color: accountColor(account),
                            imagePath: account.imagePath,
                            size: 40,
                            circle: true,
                          ),
                          const SizedBox(height: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              '${account.institution}\n••${account.accountMask}',
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: RiveroTypography.bodySmall,
                            ),
                          ),
                          if (canMove)
                            Text(
                              'Change',
                              style: RiveroTypography.bodySmall.copyWith(
                                color: RiveroColors.accent,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: RiveroSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.merchant, style: RiveroTypography.titleMedium),
                      Text(
                        DateFormat('d MMM y, h:mm a')
                            .format(t.transactionTimestamp),
                        style: RiveroTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (LedgerService.canEdit(t))
                  TextButton.icon(
                    key: const ValueKey('detail-edit'),
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: RiveroSpacing.lg),
            TextField(
              key: const ValueKey('detail-note'),
              controller: _note,
              maxLines: 3,
              minLines: 1,
              maxLength: 280,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Add a note (#tags work)',
                prefixIcon: Icon(Icons.edit_note_rounded),
                counterText: '',
              ),
            ),
            const SizedBox(height: RiveroSpacing.sm),
            if (_bill != null && File(_bill!).existsSync())
              Row(
                children: [
                  GestureDetector(
                    onTap: () => showPhoto(context, _bill!),
                    child: ClipRRect(
                      borderRadius: RiveroRadii.borderMd,
                      child: Image.file(
                        File(_bill!),
                        key: const ValueKey('bill-thumb'),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: RiveroSpacing.md),
                  TextButton(
                    onPressed: _attachBill,
                    child: const Text('Replace'),
                  ),
                  TextButton(
                    onPressed: _removeBill,
                    child: const Text('Remove'),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('attach-bill'),
                  onPressed: _attachBill,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Attach bill photo'),
                ),
              ),
            const SizedBox(height: RiveroSpacing.sm),
            if (!credit)
              Wrap(
                spacing: RiveroSpacing.sm,
                runSpacing: RiveroSpacing.xs,
                children: [
                  for (final c in cats)
                    ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  ActionChip(
                    key: const ValueKey('custom-category'),
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Custom'),
                    shape: const StadiumBorder(),
                    onPressed: () async {
                      final name = await promptNewCategory(context, ref);
                      if (name != null) setState(() => _category = name);
                    },
                  ),
                ],
              ),
            const SizedBox(height: RiveroSpacing.xl),
            if (pending)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _ignore,
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Ignore'),
                    ),
                  ),
                  const SizedBox(width: RiveroSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _confirm,
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Confirm'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  key: const ValueKey('detail-done'),
                  onPressed: _saveAndClose,
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  child: const Text('Done'),
                ),
              ),
            if (!pending &&
                !credit &&
                (t.transactionType == TransactionType.expense ||
                    t.transactionType == TransactionType.creditCardPurchase))
              Padding(
                padding: const EdgeInsets.only(top: RiveroSpacing.sm),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    key: const ValueKey('split-bill'),
                    onPressed: () async {
                      Navigator.pop(context);
                      await SplitSheet.show(context, t);
                    },
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.call_split_rounded),
                    label: const Text('Split this bill'),
                  ),
                ),
              ),
            Center(
              child: TextButton(
                onPressed: _delete,
                child: const Text(
                  'Delete entry',
                  style: TextStyle(color: RiveroColors.danger),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Amount, name and date of an entry, to correct them. Returns the new
/// values, or null when cancelled.
class _EditEntryDialog extends StatefulWidget {
  const _EditEntryDialog({required this.entry});

  final LedgerTransaction entry;

  @override
  State<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<_EditEntryDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _name;
  late DateTime _when = widget.entry.transactionTimestamp;

  @override
  void initState() {
    super.initState();
    final whole = widget.entry.amountMinorUnits.abs();
    _amount = TextEditingController(
      text: whole % 100 == 0
          ? '${whole ~/ 100}'
          : '${whole ~/ 100}.${(whole % 100).toString().padLeft(2, '0')}',
    );
    _name = TextEditingController(text: widget.entry.merchant);
  }

  @override
  void dispose() {
    _amount.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _when.isAfter(now) ? now : _when,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (d == null) return;
    // Keeps the time of day it happened.
    setState(
      () => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = parseAmountMinorUnits(_amount.text);
    final ok = value > 0 && _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Edit entry'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('edit-amount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '₹ ',
              errorText: isAmountTooLarge(_amount.text)
                  ? 'Amount too large'
                  : null,
            ),
          ),
          const SizedBox(height: RiveroSpacing.field),
          TextField(
            key: const ValueKey('edit-name'),
            controller: _name,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Paid to / received from',
              counterText: '',
            ),
          ),
          const SizedBox(height: RiveroSpacing.field),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('edit-date'),
              icon: const Icon(Icons.event_rounded),
              label: Text(DateFormat('d MMM y').format(_when)),
              onPressed: _pickDate,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('edit-save'),
          onPressed: ok
              ? () => Navigator.pop(context, (
                  amount: value,
                  name: _name.text,
                  when: _when,
                ))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
