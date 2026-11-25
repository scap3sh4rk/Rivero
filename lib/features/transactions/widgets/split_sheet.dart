import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/person_field.dart';
import 'package:rivero/design_system/widgets/picker.dart';

/// "Split this bill": who owes you what. Equal split by default (remainder
/// paise stay with you); amounts can be edited per person.
class SplitSheet extends ConsumerStatefulWidget {
  const SplitSheet(this.transaction, {super.key});

  final LedgerTransaction transaction;

  static Future<void> show(BuildContext context, LedgerTransaction t) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: RiveroColors.surface,
        builder: (_) => SplitSheet(t),
      );

  @override
  ConsumerState<SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<SplitSheet> {
  final _names = <TextEditingController>[TextEditingController()];
  final _amounts = <TextEditingController>[TextEditingController()];

  /// Where their payments are expected to land (null = cash). Starts as the
  /// account the bill was paid from.
  late String? _creditTo = widget.transaction.physicalAccountId;

  int get _bill => -widget.transaction.amountMinorUnits;

  static String _rupees(int v) => v % 100 == 0
      ? '${v ~/ 100}'
      : '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _equalise();
  }

  @override
  void dispose() {
    for (final c in [..._names, ..._amounts]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Everyone (you + the people listed) pays the same.
  void _equalise() {
    final shares = DuesService.equalShares(_bill, _names.length + 1);
    for (var i = 0; i < _amounts.length; i++) {
      _amounts[i].text = _rupees(shares[i]);
    }
    setState(() {});
  }

  void _addPerson() {
    _names.add(TextEditingController());
    _amounts.add(TextEditingController());
    _equalise();
  }

  void _removePerson(int i) {
    _names.removeAt(i).dispose();
    _amounts.removeAt(i).dispose();
    _equalise();
  }

  Future<void> _save() async {
    final shares = <String, int>{
      for (var i = 0; i < _names.length; i++)
        _names[i].text: parseAmountMinorUnits(_amounts[i].text.trim()),
    };
    try {
      await ref
          .read(duesServiceProvider)
          .splitExpense(
            transactionId: widget.transaction.id,
            shares: shares,
            creditAccountId: _creditTo,
          );
      if (mounted) Navigator.pop(context);
    } on DueValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final others = _amounts.fold<int>(
      0,
      (s, c) => s + parseAmountMinorUnits(c.text.trim()),
    );
    final yours = _bill - others;
    final people = DuesService.knownPeople(
      ref.watch(duesProvider).value ?? const [],
    );
    final accounts = (ref.watch(activePhysicalAccountsProvider).value ?? [])
        .where((a) => !a.isLiability)
        .toList();
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
              'Split ${CurrencyFormatter.format(_bill)}',
              style: RiveroTypography.titleLarge,
            ),
            Text(
              yours < 0
                  ? 'Their shares are more than the bill'
                  : 'Your share: ${CurrencyFormatter.format(yours)}',
              key: const ValueKey('your-share'),
              style: RiveroTypography.bodySmall.copyWith(
                color: yours < 0 ? RiveroColors.danger : null,
              ),
            ),
            const SizedBox(height: RiveroSpacing.lg),
            for (var i = 0; i < _names.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: PersonField(
                        key: ValueKey('split-name-$i'),
                        controller: _names[i],
                        people: people,
                        decoration: const InputDecoration(hintText: 'Name'),
                      ),
                    ),
                    const SizedBox(width: RiveroSpacing.sm),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        key: ValueKey('split-amount-$i'),
                        controller: _amounts[i],
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(prefixText: '₹'),
                      ),
                    ),
                    if (_names.length > 1)
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () => _removePerson(i),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _addPerson,
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: const Text('Add person'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _equalise,
                  child: const Text('Split equally'),
                ),
              ],
            ),
            const SizedBox(height: RiveroSpacing.md),
            PickerField<String?>(
              key: const ValueKey('split-credit-to'),
              label: 'They pay back to',
              value: _creditTo,
              options: [
                const PickerOption(null, 'Cash'),
                for (final a in accounts) PickerOption(a.id, a.name),
              ],
              onChanged: (v) => setState(() => _creditTo = v),
            ),
            const SizedBox(height: RiveroSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                key: const ValueKey('split-save'),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                onPressed: yours < 0 ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
