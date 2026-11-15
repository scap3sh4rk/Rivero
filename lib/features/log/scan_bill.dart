import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/import/bill_parser.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/storage/media_store.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/photo_picker.dart';
import 'package:rivero/design_system/widgets/picker.dart';

/// Reads the text on a photo. On-device (ML Kit); nothing is uploaded.
typedef BillTextReader = Future<String> Function(String imagePath);

final billTextReaderProvider = Provider<BillTextReader>((ref) {
  return (path) async {
    final recognizer = TextRecognizer();
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      return result.text;
    } finally {
      await recognizer.close();
    }
  };
});

/// Experimental: photo of a bill -> pre-filled entry the user confirms.
Future<void> scanBill(BuildContext context, WidgetRef ref) async {
  final path = await pickPhoto(context);
  if (path == null || !context.mounted) return;
  var text = '';
  try {
    text = await ref.read(billTextReaderProvider)(path);
  } on Object {
    text = ''; // unreadable: the form simply starts empty
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RiveroColors.surface,
    builder: (_) =>
        BillConfirmSheet(draft: parseBillText(text), imagePath: path),
  );
}

/// Check what was read from the bill, fix anything, then save.
class BillConfirmSheet extends ConsumerStatefulWidget {
  const BillConfirmSheet({
    required this.draft,
    required this.imagePath,
    super.key,
  });

  final BillDraft draft;
  final String imagePath;

  @override
  ConsumerState<BillConfirmSheet> createState() => _BillConfirmSheetState();
}

class _BillConfirmSheetState extends ConsumerState<BillConfirmSheet> {
  late final _amount = TextEditingController(
    text: widget.draft.amountMinorUnits == null
        ? ''
        : _rupees(widget.draft.amountMinorUnits!),
  );
  late final _what = TextEditingController(text: widget.draft.merchant ?? '');
  late DateTime _date = widget.draft.date ?? DateTime.now();
  late String _category = widget.draft.category ?? 'Other';
  String? _accountId;

  static String _rupees(int v) => v % 100 == 0
      ? '${v ~/ 100}'
      : '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _amount.dispose();
    _what.dispose();
    super.dispose();
  }

  Future<void> _save(String accountId, bool card) async {
    final minor = parseAmountMinorUnits(_amount.text.trim());
    if (minor <= 0) return;
    final stored = await MediaStore.keep(
      widget.imagePath,
      folder: MediaStore.bills,
      name: 'scan',
    );
    final what = _what.text.trim();
    await ref
        .read(ledgerServiceProvider)
        .recordManual(
          accountId: accountId,
          amountMinorUnits: -minor,
          type: card
              ? TransactionType.creditCardPurchase
              : TransactionType.expense,
          merchant: what.isEmpty ? _category : what,
          category: _category,
          at: _date,
          attachmentPath: stored,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref.watch(activePhysicalAccountsProvider).value ?? const [];
    final account =
        accounts.where((a) => a.id == _accountId).firstOrNull ??
        accounts
            .where((a) => a.id == ref.read(lastLogAccountProvider))
            .firstOrNull ??
        accounts.where((a) => !a.isLiability).firstOrNull;
    final categories = {
      ...ref.watch(logCategoriesProvider).map((c) => c.name),
      _category,
    }.toList();
    final readNothing = widget.draft.amountMinorUnits == null;

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
            Text('Check the bill', style: RiveroTypography.titleLarge),
            Text(
              readNothing
                  ? 'Could not read an amount. Fill it in below.'
                  : 'Read from your photo. Fix anything that is off.',
              style: RiveroTypography.bodySmall,
            ),
            const SizedBox(height: RiveroSpacing.lg),
            TextField(
              key: const ValueKey('bill-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹',
              ),
            ),
            const SizedBox(height: RiveroSpacing.field),
            TextField(
              key: const ValueKey('bill-what'),
              controller: _what,
              decoration: const InputDecoration(labelText: 'What was it for?'),
            ),
            const SizedBox(height: RiveroSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(DateFormat('d MMM y').format(_date)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            Wrap(
              spacing: RiveroSpacing.sm,
              runSpacing: RiveroSpacing.xs,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    label: Text(c),
                    selected: _category == c,
                    showCheckmark: false,
                    shape: const StadiumBorder(),
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            if (accounts.isNotEmpty) ...[
              const SizedBox(height: RiveroSpacing.field),
              PickerField<String>(
                label: 'Paid from',
                value: account?.id,
                options: [for (final a in accounts) PickerOption(a.id, a.name)],
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ],
            const SizedBox(height: RiveroSpacing.xl),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                key: const ValueKey('bill-save'),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                onPressed: account == null
                    ? null
                    : () => _save(account.id, account.isLiability),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
