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
import 'package:rivero/features/owed/bills_and_commitments.dart';

/// Money in both directions: what people owe you, what you owe them, and
/// every bill you have to pay (cards, autopay, loans).
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
    bool isOpen(Due d) => d.status == DueStatus.open;
    final toYou = dues.where((d) => d.kind != DueKind.borrowed).toList();
    final byYou = dues.where((d) => d.kind == DueKind.borrowed).toList();
    final toYouOpen = toYou.where(isOpen).toList();
    final byYouOpen = byYou.where(isOpen).toList();
    final closed = dues.where((d) => !isOpen(d)).toList();
    final owedToYou = DuesService.totalOutstanding(dues);
    final youOwe = DuesService.totalYouOwe(dues);

    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(
        top: RiveroSpacing.xl,
        bottom: RiveroSpacing.sm,
      ),
      child: Text(text, style: RiveroTypography.titleMedium),
    );

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Owed',
        showProfile: asTab,
        leading: asTab
            ? null
            : BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: [
          PopupMenuButton<bool>(
            key: const ValueKey('owed-add'),
            tooltip: 'Add',
            icon: const Icon(Icons.add_rounded),
            onSelected: (borrowing) =>
                _MoneySheet.show(context, borrowing: borrowing),
            itemBuilder: (_) => const [
              PopupMenuItem(
                key: ValueKey('add-lent'),
                value: false,
                child: Text('I lent money'),
              ),
              PopupMenuItem(
                key: ValueKey('add-borrowed'),
                value: true,
                child: Text('I borrowed money'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: _Total(
                  label: 'Owed to you',
                  value: money(owedToYou),
                  valueKey: const ValueKey('owed-total'),
                  color: RiveroColors.success,
                ),
              ),
              const SizedBox(width: RiveroSpacing.md),
              Expanded(
                child: _Total(
                  label: 'You owe people',
                  value: money(youOwe),
                  valueKey: const ValueKey('owe-total'),
                  color: youOwe > 0 ? RiveroColors.warning : null,
                ),
              ),
            ],
          ),
          header('People who owe you'),
          if (toYouOpen.isEmpty)
            Text(
              'Split a bill: open any payment in Activity and tap '
              '"Split this bill". Lent money? Tap + above.',
              style: RiveroTypography.bodySmall,
            ),
          for (final d in toYouOpen) _DueTile(d, money: money),
          header('People you owe'),
          if (byYouOpen.isEmpty)
            Text(
              'Borrowed from someone? Tap + above and note when you will '
              'pay it back.',
              style: RiveroTypography.bodySmall,
            ),
          for (final d in byYouOpen) _DueTile(d, money: money),
          header('Bills & commitments'),
          const BillsAndCommitments(),
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

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.value,
    required this.valueKey,
    this.color,
  });

  final String label;
  final String value;
  final Key valueKey;
  final Color? color;

  @override
  Widget build(BuildContext context) => RiveroCard(
    isElevated: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: RiveroTypography.bodySmall),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            key: valueKey,
            style: RiveroTypography.financialMedium.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

class _DueTile extends StatelessWidget {
  const _DueTile(this.d, {required this.money});

  final Due d;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) {
    final owed = d.amountMinorUnits - d.receivedMinorUnits;
    final open = d.status == DueStatus.open;
    final borrowed = d.kind == DueKind.borrowed;
    final what = borrowed
        ? 'Borrowed'
        : d.kind == DueKind.lent
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
                      '$what · ${DateFormat('d MMM').format(d.createdAt)}'
                      '${borrowed && d.dueDate != null && open ? ' · pay by ${DateFormat('d MMM').format(d.dueDate!)}' : ''}',
                      style: RiveroTypography.bodySmall,
                    ),
                    if (d.receivedMinorUnits > 0 && open)
                      Text(
                        borrowed
                            ? '${money(d.receivedMinorUnits)} of '
                                  '${money(d.amountMinorUnits)} paid'
                            : '${money(d.receivedMinorUnits)} of '
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
  String?
  _paidFrom; // borrowed money: the account it is repaid from (null = cash)

  static String _rupees(int v) => v % 100 == 0
      ? '${v ~/ 100}'
      : '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    if (widget.due.kind == DueKind.borrowed) return;
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

  /// Money you owe: pay back some or all, from an account or in cash.
  Widget _borrowedBody(String Function(int) money) {
    final service = ref.read(duesServiceProvider);
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
          Text(
            'You owe ${widget.due.person} ${money(_owed)}',
            style: RiveroTypography.titleLarge,
          ),
          const SizedBox(height: RiveroSpacing.lg),
          TextField(
            key: const ValueKey('repay-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount paid back',
              prefixText: '₹',
            ),
          ),
          const SizedBox(height: RiveroSpacing.md),
          PickerField<String?>(
            label: 'Paid from',
            value: _paidFrom,
            options: [
              const PickerOption(null, 'Cash'),
              for (final a in accounts) PickerOption(a.id, a.name),
            ],
            onChanged: (v) => setState(() => _paidFrom = v),
          ),
          const SizedBox(height: RiveroSpacing.xl),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              key: const ValueKey('repay-save'),
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: () => _run(
                () => service.repay(
                  widget.due.id,
                  parseAmountMinorUnits(_amount.text.trim()),
                  accountId: _paidFrom,
                ),
              ),
              child: const Text('Mark paid back'),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => _run(() => service.writeOff(widget.due.id)),
              child: const Text('They forgave it'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(duesServiceProvider);
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    if (widget.due.kind == DueKind.borrowed) return _borrowedBody(money);
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

/// "I lent money" or "I borrowed money": who, how much, which account (or
/// cash) and, for borrowed money, when it is due back.
class _MoneySheet extends ConsumerStatefulWidget {
  const _MoneySheet({required this.borrowing});

  final bool borrowing;

  static Future<void> show(BuildContext context, {required bool borrowing}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: RiveroColors.surface,
        builder: (_) => _MoneySheet(borrowing: borrowing),
      );

  @override
  ConsumerState<_MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends ConsumerState<_MoneySheet> {
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _accountId;
  DateTime? _dueDate;

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final service = ref.read(duesServiceProvider);
    final minor = parseAmountMinorUnits(_amount.text.trim());
    final note = _note.text.trim().isEmpty ? null : _note.text;
    try {
      if (widget.borrowing) {
        await service.borrow(
          person: _person.text,
          amountMinorUnits: minor,
          accountId: _accountId,
          dueDate: _dueDate,
          note: note,
        );
      } else {
        await service.lend(
          person: _person.text,
          amountMinorUnits: minor,
          accountId: _accountId,
          note: note,
        );
      }
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
    final borrowing = widget.borrowing;
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
          Text(
            borrowing ? 'Borrowed money' : 'Lent money',
            style: RiveroTypography.titleLarge,
          ),
          const SizedBox(height: RiveroSpacing.lg),
          TextField(
            key: const ValueKey('lend-person'),
            controller: _person,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: borrowing ? 'From' : 'To'),
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
            label: borrowing ? 'Received in' : 'From',
            value: _accountId,
            options: [
              const PickerOption(null, 'Cash'),
              for (final a in accounts) PickerOption(a.id, a.name),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          if (borrowing) ...[
            const SizedBox(height: RiveroSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('due-date-button'),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? now.add(const Duration(days: 30)),
                  firstDate: now,
                  lastDate: DateTime(now.year + 10),
                );
                if (d != null) setState(() => _dueDate = d);
              },
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
              icon: const Icon(Icons.event_rounded),
              label: Text(
                _dueDate == null
                    ? 'Pay back by (optional)'
                    : 'Pay back by ${DateFormat('d MMM yyyy').format(_dueDate!)}',
              ),
            ),
          ],
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
              key: const ValueKey('money-save'),
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
