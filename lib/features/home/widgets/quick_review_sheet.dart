import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Add a captured payment in two taps: pick a category, optionally a note,
/// then Add (or Ignore). Opened from a capture notification ("Open Rivero")
/// or by tapping a payment waiting in "To review".
class QuickReviewSheet extends ConsumerStatefulWidget {
  const QuickReviewSheet(this.transactionId, {super.key});

  final String transactionId;

  static Future<void> show(BuildContext context, String transactionId) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: RiveroColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => QuickReviewSheet(transactionId),
      );

  @override
  ConsumerState<QuickReviewSheet> createState() => _QuickReviewSheetState();
}

class _QuickReviewSheetState extends ConsumerState<QuickReviewSheet> {
  final _note = TextEditingController();
  String? _category;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(LedgerTransaction t, {required bool add}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    final ledger = ref.read(ledgerServiceProvider);
    if (add) {
      final note = _note.text.trim();
      await (db.update(db.transactions)..where((x) => x.id.equals(t.id))).write(
        TransactionsCompanion(
          category: _category == null
              ? const Value.absent()
              : Value(_category!),
          userNotes: note.isEmpty ? const Value.absent() : Value(note),
        ),
      );
      await ledger.confirm(t.id);
      await ref.read(reconciliationServiceProvider).reconcileAll();
    } else {
      await ledger.ignore(t.id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(allTransactionsStreamProvider).value ?? const [];
    final t = txns.where((x) => x.id == widget.transactionId).firstOrNull;
    final privacy = ref.watch(privacyModeProvider);
    final categories = ref.watch(logCategoriesProvider).map((c) => c.name);
    if (t == null) return const SizedBox(height: 160);
    final income = t.amountMinorUnits > 0;
    final waiting = t.transactionState == TransactionState.needsReview;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        RiveroSpacing.xl,
        RiveroSpacing.xl,
        RiveroSpacing.xl,
        MediaQuery.viewInsetsOf(context).bottom + RiveroSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            privacy
                ? '₹••••'
                : '${income ? '+' : ''}'
                      '${CurrencyFormatter.format(t.amountMinorUnits.abs())}',
            key: const ValueKey('quick-amount'),
            style: RiveroTypography.financialLarge.copyWith(
              color: income ? RiveroColors.success : null,
            ),
          ),
          Text(
            '${t.merchant} · '
            '${DateFormat('d MMM, h:mm a').format(t.transactionTimestamp)}',
            style: RiveroTypography.bodySmall,
          ),
          const SizedBox(height: RiveroSpacing.lg),
          Wrap(
            spacing: RiveroSpacing.sm,
            runSpacing: RiveroSpacing.xs,
            children: [
              for (final c in categories)
                ChoiceChip(
                  key: ValueKey('quick-cat-$c'),
                  label: Text(c),
                  selected: _category == c,
                  showCheckmark: false,
                  shape: const StadiumBorder(),
                  onSelected: (on) => setState(() => _category = on ? c : null),
                ),
            ],
          ),
          const SizedBox(height: RiveroSpacing.md),
          TextField(
            key: const ValueKey('quick-note'),
            controller: _note,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Add a note (optional)',
              counterText: '',
            ),
          ),
          const SizedBox(height: RiveroSpacing.lg),
          Row(
            children: [
              if (waiting) ...[
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('quick-ignore'),
                    onPressed: () => _decide(t, add: false),
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('Ignore'),
                  ),
                ),
                const SizedBox(width: RiveroSpacing.sm),
              ],
              Expanded(
                child: FilledButton(
                  key: const ValueKey('quick-add'),
                  onPressed: () => _decide(t, add: true),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(waiting ? 'Add' : 'Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
