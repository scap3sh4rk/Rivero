import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/picker.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Money that should come back to you: split bills and money lent.
class OwedScreen extends ConsumerWidget {
  const OwedScreen({super.key, this.asTab = false});

  /// Shown as a main tab (no back button, profile button visible).
  final bool asTab;

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const OwedScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dues = ref.watch(duesProvider).value ?? const [];
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final open = dues.where((d) => d.status == DueStatus.open).toList();
    final closed = dues.where((d) => d.status != DueStatus.open).toList();

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Owed to you',
        showProfile: asTab,
        leading: asTab
            ? null
            : BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: [
          IconButton(
            tooltip: 'Lent money',
            onPressed: () => _LendSheet.show(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge,
        ),
        children: [
          Text('Still to come back', style: RiveroTypography.bodyMedium),
          Text(
            money(DuesService.totalOutstanding(dues)),
            key: const ValueKey('owed-total'),
            style: RiveroTypography.financialLarge,
          ),
          const SizedBox(height: RiveroSpacing.xl),
          if (dues.isEmpty)
            Text(
              'Split a bill: open any payment in Activity and tap '
              '"Split this bill". Lent money? Tap + above.',
              style: RiveroTypography.bodySmall,
            ),
          for (final d in open) _DueTile(d, money: money),
          if (closed.isNotEmpty)
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Settled & written off · ${closed.length}',
                  style: RiveroTypography.bodyMedium,
                ),
                children: [for (final d in closed) _DueTile(d, money: money)],
              ),
            ),
        ],
      ),
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile(this.d, {required this.money});

  final Due d;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) {
    final owed = d.amountMinorUnits - d.receivedMinorUnits;
    final open = d.status == DueStatus.open;
    final what = d.kind == DueKind.lent
        ? 'Lent'
        : 'Share of ${d.note ?? 'a bill'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
      child: RiveroCard(
        onTap: open ? () => _DueSheet.show(context, d) : null,
        child: Opacity(
          opacity: open ? 1 : 0.55,
          child: Row(
            children: [
              BankBadge(name: d.person, size: 40, circle: true),
              const SizedBox(width: RiveroSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.person, style: RiveroTypography.bodyLarge),
                    Text(
                      '$what · ${DateFormat('d MMM').format(d.createdAt)}',
                      style: RiveroTypography.bodySmall,
                    ),
                    if (d.receivedMinorUnits > 0 && open)
                      Text(
                        '${money(d.receivedMinorUnits)} of '
                        '${money(d.amountMinorUnits)} back',
                        style: RiveroTypography.bodySmall,
                      ),
                  ],
                ),
              ),
              Text(
                open
                    ? money(owed)
                    : d.status == DueStatus.settled
                    ? 'Settled'
                    : 'Written off',
                style: RiveroTypography.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mark money received (matched to a payment, or in cash), or write it off.
class _DueSheet extends ConsumerStatefulWidget {
  const _DueSheet(this.due);

  final Due due;

  static Future<void> show(BuildContext context, Due d) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: RiveroColors.surface,
        builder: (_) => _DueSheet(d),
      );

  @override
  ConsumerState<_DueSheet> createState() => _DueSheetState();
}

class _DueSheetState extends ConsumerState<_DueSheet> {
  late final int _owed =
      widget.due.amountMinorUnits - widget.due.receivedMinorUnits;
  late final _amount = TextEditingController(text: _rupees(_owed));
  List<LedgerTransaction> _candidates = const [];
  String? _matched;

  static String _rupees(int v) => v % 100 == 0
      ? '${v ~/ 100}'
      : '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    ref.read(duesServiceProvider).repaymentCandidates(widget.due.id).then((c) {
      if (mounted) setState(() => _candidates = c);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
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
    final service = ref.read(duesServiceProvider);
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
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
            '${widget.due.person} owes ${money(_owed)}',
            style: RiveroTypography.titleLarge,
          ),
          const SizedBox(height: RiveroSpacing.lg),
          TextField(
            key: const ValueKey('receive-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount received',
              prefixText: '₹',
            ),
          ),
          if (_candidates.isNotEmpty) ...[
            const SizedBox(height: RiveroSpacing.md),
            Text('Match a payment you got', style: RiveroTypography.bodySmall),
            const SizedBox(height: RiveroSpacing.xs),
            Wrap(
              spacing: RiveroSpacing.sm,
              runSpacing: RiveroSpacing.xs,
              children: [
                for (final t in _candidates)
                  ChoiceChip(
                    label: Text(
                      '${money(t.amountMinorUnits)} · ${t.merchant} · '
                      '${DateFormat('d MMM').format(t.transactionTimestamp)}',
                    ),
                    selected: _matched == t.id,
                    showCheckmark: false,
                    shape: const StadiumBorder(),
                    onSelected: (on) => setState(() {
                      _matched = on ? t.id : null;
                      if (on) _amount.text = _rupees(t.amountMinorUnits);
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: RiveroSpacing.xl),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: () => _run(
                () => service.receive(
                  widget.due.id,
                  parseAmountMinorUnits(_amount.text.trim()),
                  creditTransactionId: _matched,
                ),
              ),
              child: Text(
                _matched == null ? 'Received in cash' : 'Mark received',
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => _run(() => service.writeOff(widget.due.id)),
              child: const Text(
                'Write off',
                style: TextStyle(color: RiveroColors.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "I lent money": who, how much, and from which account (or cash).
class _LendSheet extends ConsumerStatefulWidget {
  const _LendSheet();

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RiveroColors.surface,
    builder: (_) => const _LendSheet(),
  );

  @override
  ConsumerState<_LendSheet> createState() => _LendSheetState();
}

class _LendSheetState extends ConsumerState<_LendSheet> {
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _accountId;

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lent money', style: RiveroTypography.titleLarge),
          const SizedBox(height: RiveroSpacing.lg),
          TextField(
            key: const ValueKey('lend-person'),
            controller: _person,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'To'),
          ),
          const SizedBox(height: RiveroSpacing.md),
          TextField(
            key: const ValueKey('lend-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '₹',
            ),
          ),
          const SizedBox(height: RiveroSpacing.md),
          PickerField<String?>(
            label: 'From',
            value: _accountId,
            options: [
              const PickerOption(null, 'Cash'),
              for (final a in accounts) PickerOption(a.id, a.name),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: RiveroSpacing.md),
          TextField(
            controller: _note,
            decoration: const InputDecoration(hintText: 'Note (optional)'),
          ),
          const SizedBox(height: RiveroSpacing.xl),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: () async {
                try {
                  await ref
                      .read(duesServiceProvider)
                      .lend(
                        person: _person.text,
                        amountMinorUnits: parseAmountMinorUnits(
                          _amount.text.trim(),
                        ),
                        accountId: _accountId,
                        note: _note.text.trim().isEmpty ? null : _note.text,
                      );
                  if (context.mounted) Navigator.pop(context);
                } on DueValidationException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
