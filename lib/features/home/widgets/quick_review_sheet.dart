import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/rules/capture_rules.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/picker.dart';
import 'package:rivero/features/transactions/widgets/undo.dart';

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
  String? _accountId; // set when the user corrects Rivero's guess
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
      // Waiting or already counted: moved to the right account either way.
      final account = _accountId;
      if (account != null && account != t.physicalAccountId) {
        await ledger.changeAccount(t.id, account);
      }
      await ledger.confirm(t.id);
      await ref.read(reconciliationServiceProvider).reconcileAll();
      final category = _category;
      final rules = CaptureRules(db);
      if (category != null &&
          await rules.shouldSuggest(t.merchant, category) &&
          mounted) {
        // Filed the same payee the same way twice: offer a rule.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Always put ${t.merchant} in $category?'),
            duration: const Duration(seconds: 8),
            persist: false, // goes after 8 s even though it has a button
            action: SnackBarAction(
              label: 'Make a rule',
              onPressed: () => rules.add(
                CaptureRule(contains: t.merchant, category: category),
              ),
            ),
          ),
        );
      }
    } else if (mounted) {
      await ignoreWithUndo(context, t.id);
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
    // Already filed under one of the user's categories (a rule, or saved
    // before): that one is picked. A guess from the message is not.
    final picked =
        _category ?? (categories.contains(t.category) ? t.category : null);
    final income = t.amountMinorUnits > 0;
    final waiting = t.transactionState == TransactionState.needsReview;
    // Any account it could have been (a bank, a card, cash).
    final choices = ref.watch(activePhysicalAccountsProvider).value ?? const [];

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
          Text(
            picked == null ? 'Pick a category' : 'Category',
            style: RiveroTypography.bodySmall.copyWith(
              color: picked == null ? RiveroColors.warning : null,
            ),
          ),
          const SizedBox(height: RiveroSpacing.xs),
          Wrap(
            spacing: RiveroSpacing.sm,
            runSpacing: RiveroSpacing.xs,
            children: [
              for (final c in categories)
                ChoiceChip(
                  key: ValueKey('quick-cat-$c'),
                  label: Text(c),
                  selected: picked == c,
                  showCheckmark: false,
                  shape: const StadiumBorder(),
                  onSelected: (on) => setState(() => _category = on ? c : null),
                ),
            ],
          ),
          if (!t.isInternalTransfer && choices.length > 1) ...[
            const SizedBox(height: RiveroSpacing.md),
            PickerField<String>(
              key: const ValueKey('quick-account'),
              label: income ? 'Received in' : 'Paid from',
              value: _accountId ?? t.physicalAccountId,
              options: [for (final a in choices) PickerOption(a.id, a.name)],
              onChanged: (v) => setState(() => _accountId = v),
            ),
          ],
          const SizedBox(height: RiveroSpacing.md),
          TextField(
            key: const ValueKey('quick-note'),
            controller: _note,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Description (optional)',
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
                  // A category is required; the description is extra.
                  onPressed: picked == null
                      ? null
                      : () {
                          _category = picked;
                          _decide(t, add: true);
                        },
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
