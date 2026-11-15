import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/storage/media_store.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/photo_picker.dart';
import 'package:rivero/design_system/widgets/picker.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/rivero_fab.dart';
import 'package:rivero/features/mandates/mandates_screen.dart';
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
    final accounts =
        ref.watch(activePhysicalAccountsProvider).value ?? const [];
    final mandates = ref.watch(activeMandatesProvider).value ?? const [];
    final cycle = ref.watch(currentPaycycleProvider);
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final owedToYou = DuesService.totalOutstanding(dues);
    final youOwe = DuesService.totalYouOwe(dues);
    final bills = CommitmentTotals.of(
      ref.watch(exchangeRatesProvider).inHome(accounts),
      mandates,
      cycle.cycleEndDate,
      DateTime.now(),
    );
    final openToYou = dues
        .where((d) => d.status == DueStatus.open && d.kind != DueKind.borrowed)
        .toList();
    final openByYou = dues
        .where((d) => d.status == DueStatus.open && d.kind == DueKind.borrowed)
        .toList();
    final net = owedToYou - youOwe;
    final nextAutopay = ([
      ...mandates,
    ]..removeWhere((m) => m.nextExecutionDate == null)).firstOrNull;

    Widget stat(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: RiveroSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: RiveroTypography.bodySmall)),
          Text(value, style: RiveroTypography.bodyMedium),
        ],
      ),
    );
    String people(int n) => n == 1 ? '1 person' : '$n people';
    Due? oldest(List<Due> l) => l.isEmpty
        ? null
        : (l.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt)))
              .first;
    final oldestToYou = oldest(openToYou);
    final oldestByYou = oldest(openByYou);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Owed',
        showProfile: asTab,
        leading: asTab
            ? null
            : BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      floatingActionButton: RiveroFab(
        tooltip: 'Add',
        onPressed: () => _chooseKind(context),
      ),
      // Everything fits on one screen: the two frames share the height
      // above the net line and the + button; nothing to scroll.
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          RiveroSpacing.sm,
          RiveroSpacing.xl,
          88,
        ),
        child: Column(
          children: [
            Expanded(
              child: _Total(
                key: const ValueKey('owed-card-to-you'),
                label: 'Owed to you',
                value: money(owedToYou),
                valueKey: const ValueKey('owed-total'),
                color: RiveroColors.success,
                details: [
                  stat(
                    'Owed by',
                    openToYou.isEmpty ? 'Nobody' : people(openToYou.length),
                  ),
                  if (oldestToYou != null)
                    stat(
                      'Oldest',
                      '${oldestToYou.person} · ${DateFormat('d MMM').format(oldestToYou.createdAt)}',
                    ),
                ],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OwedToYouScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: RiveroSpacing.md),
            Expanded(
              child: _Total(
                key: const ValueKey('owed-card-you-owe'),
                label: 'You owe people',
                value: money(youOwe),
                valueKey: const ValueKey('owe-total'),
                color: youOwe > 0 ? RiveroColors.warning : null,
                details: [
                  stat(
                    'Owed to',
                    openByYou.isEmpty ? 'Nobody' : people(openByYou.length),
                  ),
                  if (oldestByYou != null)
                    stat(
                      'Oldest',
                      '${oldestByYou.person} · ${DateFormat('d MMM').format(oldestByYou.createdAt)}',
                    ),
                  stat('Card bills', money(bills.cards + bills.loans)),
                  stat('Autopay before payday', money(bills.autopay)),
                ],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const YouOweScreen()),
                ),
              ),
            ),
            const SizedBox(height: RiveroSpacing.md),
            RiveroCard(
              key: const ValueKey('owed-net'),
              child: Row(
                children: [
                  Icon(
                    net == 0
                        ? Icons.balance_rounded
                        : net > 0
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: net == 0
                        ? RiveroColors.textSecondary
                        : net > 0
                        ? RiveroColors.success
                        : RiveroColors.warning,
                  ),
                  const SizedBox(width: RiveroSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          net == 0
                              ? 'All square'
                              : net > 0
                              ? 'Net: you are owed ${money(net)}'
                              : 'Net: you owe ${money(-net)}',
                          key: const ValueKey('owed-net-text'),
                          style: RiveroTypography.titleMedium,
                        ),
                        Text(
                          net < 0
                              ? 'to settle after what people owe you'
                              : 'between people, before bills',
                          style: RiveroTypography.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: RiveroSpacing.sm),
            // Autopay lives here: SIPs, subscriptions, EMIs and bills that
            // leave your accounts on their own.
            RiveroCard(
              key: const ValueKey('owed-autopay'),
              onTap: () => MandatesScreen.open(context),
              child: Row(
                children: [
                  Icon(Icons.autorenew_rounded, color: RiveroColors.accent),
                  const SizedBox(width: RiveroSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Autopay', style: RiveroTypography.titleMedium),
                        Text(
                          mandates.isEmpty
                              ? 'SIPs, subscriptions, EMIs and bills'
                              : '${mandates.length} active'
                                    '${nextAutopay == null ? '' : ' · next ${nextAutopay.payee}, ${DateFormat('d MMM').format(nextAutopay.nextExecutionDate!)}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RiveroTypography.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: RiveroColors.textMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The plus on the Owed page: which kind of entry to add.
  static Future<void> _chooseKind(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: RiveroColors.surface,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('add-lent'),
                leading: const Icon(Icons.call_made_rounded),
                title: const Text('I lent money'),
                onTap: () {
                  Navigator.pop(ctx);
                  _MoneySheet.show(context, borrowing: false);
                },
              ),
              ListTile(
                key: const ValueKey('add-borrowed'),
                leading: const Icon(Icons.call_received_rounded),
                title: const Text('I borrowed money'),
                onTap: () {
                  Navigator.pop(ctx);
                  _MoneySheet.show(context, borrowing: true);
                },
              ),
            ],
          ),
        ),
      );
}

/// Everyone who owes you (split bills, loans). The plus adds a loan.
class OwedToYouScreen extends ConsumerWidget {
  const OwedToYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dues = ref.watch(duesProvider).value ?? const [];
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final mine = dues.where((d) => d.kind != DueKind.borrowed).toList();
    final open = mine.where((d) => d.status == DueStatus.open).toList();
    final closed = mine.where((d) => d.status != DueStatus.open).toList();
    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Owed to you',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      floatingActionButton: RiveroFab(
        tooltip: 'I lent money',
        onPressed: () => _MoneySheet.show(context, borrowing: false),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge + 72 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            money(DuesService.totalOutstanding(dues)),
            style: RiveroTypography.financialLarge.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: RiveroSpacing.lg),
          for (final d in open) _DueTile(d, money: money),
          if (closed.isNotEmpty) _ClosedList(closed, money: money),
        ],
      ),
    );
  }
}

/// Everything you owe: people you borrowed from, and every bill to pay
/// (cards, loans, autopay). The plus records borrowed money.
class YouOweScreen extends ConsumerWidget {
  const YouOweScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dues = ref.watch(duesProvider).value ?? const [];
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final mine = dues.where((d) => d.kind == DueKind.borrowed).toList();
    final open = mine.where((d) => d.status == DueStatus.open).toList();
    final closed = mine.where((d) => d.status != DueStatus.open).toList();
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
        title: 'You owe people',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      floatingActionButton: RiveroFab(
        tooltip: 'I borrowed money',
        onPressed: () => _MoneySheet.show(context, borrowing: true),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge + 72 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            money(DuesService.totalYouOwe(dues)),
            style: RiveroTypography.financialLarge.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (open.isNotEmpty) header('People'),
          for (final d in open) _DueTile(d, money: money),
          header('Bills & commitments'),
          const BillsAndCommitments(),
          if (closed.isNotEmpty) _ClosedList(closed, money: money),
        ],
      ),
    );
  }
}

class _ClosedList extends StatelessWidget {
  const _ClosedList(this.closed, {required this.money});

  final List<Due> closed;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Settled & written off · ${closed.length}',
        style: RiveroTypography.bodyMedium,
      ),
      children: [for (final d in closed) _DueTile(d, money: money)],
    ),
  );
}

/// One of the two big frames on the Owed page.
class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.value,
    required this.valueKey,
    required this.onTap,
    required this.details,
    super.key,
    this.color,
  });

  final String label;
  final String value;
  final Key valueKey;
  final VoidCallback onTap;
  final Color? color;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) => RiveroCard(
    isElevated: true,
    onTap: onTap,
    child: SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: RiveroTypography.titleMedium)),
              Icon(Icons.chevron_right_rounded, color: RiveroColors.textMuted),
            ],
          ),
          // The amount takes the free space and shrinks only if it must.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  key: valueKey,
                  style: RiveroTypography.financialLarge.copyWith(
                    color: color,
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          ...details,
        ],
      ),
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
              BankBadge(
                name: d.person,
                size: 40,
                circle: true,
                bankIcon: false,
              ),
              const SizedBox(width: RiveroSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.person, style: RiveroTypography.bodyLarge),
                    Text(
                      '$what · ${DateFormat('d MMM').format(d.createdAt)}'
                      '${borrowed && d.dueDate != null && open ? ' · pay by ${DateFormat('d MMM').format(d.dueDate!)}' : ''}'
                      '${d.attachmentPath != null ? ' · photo' : ''}',
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

  /// The bill or proof photo, if one was attached; tap to view it.
  Widget _proof() {
    final path = widget.due.attachmentPath;
    if (path == null || !File(path).existsSync()) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.lg),
      child: GestureDetector(
        key: const ValueKey('due-proof'),
        onTap: () => showPhoto(context, path),
        child: ClipRRect(
          borderRadius: RiveroRadii.borderLg,
          child: Image.file(
            File(path),
            height: 120,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
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
          _proof(),
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
          _proof(),
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
  DateTime _on = DateTime.now(); // the day it really happened
  String? _proof; // a photo of the bill or proof

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
      // Keep the photo in app storage (it lives as long as the entry).
      final proof = _proof == null
          ? null
          : await MediaStore.keep(
              _proof!,
              folder: MediaStore.bills,
              name: 'due-${DateTime.now().microsecondsSinceEpoch}',
            );
      if (widget.borrowing) {
        await service.borrow(
          person: _person.text,
          amountMinorUnits: minor,
          accountId: _accountId,
          dueDate: _dueDate,
          note: note,
          on: _on,
          attachmentPath: proof,
        );
      } else {
        await service.lend(
          person: _person.text,
          amountMinorUnits: minor,
          accountId: _accountId,
          note: note,
          on: _on,
          attachmentPath: proof,
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
          const SizedBox(height: RiveroSpacing.md),
          OutlinedButton.icon(
            key: const ValueKey('happened-date-button'),
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _on,
                firstDate: DateTime(now.year - 5),
                lastDate: now,
              );
              if (d != null) setState(() => _on = d);
            },
            style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
            icon: const Icon(Icons.today_rounded),
            label: Text(
              DateUtils.isSameDay(_on, DateTime.now())
                  ? 'Date: today'
                  : 'Date: ${DateFormat('d MMM yyyy').format(_on)}',
            ),
          ),
          const SizedBox(height: RiveroSpacing.sm),
          OutlinedButton.icon(
            key: const ValueKey('proof-button'),
            onPressed: () async {
              final picked = await pickPhoto(context);
              if (picked != null) setState(() => _proof = picked);
            },
            style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
            icon: Icon(
              _proof == null
                  ? Icons.add_a_photo_outlined
                  : Icons.check_circle_rounded,
            ),
            label: Text(
              _proof == null
                  ? 'Add a bill or proof (optional)'
                  : 'Photo attached',
            ),
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
