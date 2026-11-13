import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/features/transactions/widgets/split_sheet.dart';

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

  static const categories = [
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Health',
    'Fun',
    'Other',
  ];

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

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'Balances and your budget are corrected as if it never happened.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(ledgerServiceProvider).remove(widget.transaction.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirm() async {
    await ref.read(ledgerServiceProvider).confirm(widget.transaction.id);
    await ref.read(reconciliationServiceProvider).reconcileAll();
    await _saveAndClose();
  }

  Future<void> _ignore() async {
    await _db.transactionsDao.updateTransactionState(
      widget.transaction.id,
      TransactionState.ignored,
    );
    await _saveAndClose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    final privacy = ref.watch(privacyModeProvider);
    final account =
        (ref.watch(activePhysicalAccountsProvider).value ?? const [])
            .where((a) => a.id == t.physicalAccountId)
            .firstOrNull;
    final pending = t.transactionState == TransactionState.needsReview;
    final credit = t.amountMinorUnits > 0;
    final cats = {...TransactionDetailSheet.categories, t.category}.toList();

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
            Text(
              privacy
                  ? '₹••••'
                  : '${credit ? '+' : ''}'
                        '${CurrencyFormatter.format(t.amountMinorUnits.abs())}',
              style: RiveroTypography.financialLarge.copyWith(
                color: credit ? RiveroColors.success : null,
              ),
            ),
            const SizedBox(height: RiveroSpacing.xs),
            Text(t.merchant, style: RiveroTypography.titleMedium),
            Text(
              '${DateFormat('d MMM y, h:mm a').format(t.transactionTimestamp)}'
              '${account == null ? '' : ' · ${account.name}'}',
              style: RiveroTypography.bodySmall,
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
                hintText: 'Add a note',
                prefixIcon: Icon(Icons.edit_note_rounded),
                counterText: '',
              ),
            ),
            const SizedBox(height: RiveroSpacing.md),
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
