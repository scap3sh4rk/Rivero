import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/mandates/autopay_actions.dart';
import 'package:rivero/core/mandates/subscription_finder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/picker.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/rivero_fab.dart';
import 'package:uuid/uuid.dart';

/// One place for every autopay / e-NACH commitment, across all banks.
/// Cancelling happens in the bank app; here the user records that it happened.
class MandatesScreen extends ConsumerWidget {
  const MandatesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const MandatesScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mandates = ref.watch(allMandatesProvider).value ?? const [];
    final isPrivacy = ref.watch(privacyModeProvider);
    final live = mandates
        .where(
          (m) =>
              m.status == MandateStatus.active ||
              m.status == MandateStatus.registered,
        )
        .toList();
    final inactive = mandates.where((m) => !live.contains(m)).toList();
    final reserved = live.fold<int>(0, (s, m) => s + mandateReserve(m));

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: const RiveroAppBar(
        title: 'Autopay',
        subtitle: 'Every recurring debit, one place',
      ),
      floatingActionButton: RiveroFab(
        tooltip: 'Add autopay',
        onPressed: () => _MandateSheet.show(context),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(RiveroSpacing.lg),
        children: [
          RiveroCard(
            isElevated: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COMMITTED PER CYCLE',
                  style: RiveroTypography.labelSmall.copyWith(
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: RiveroSpacing.xs),
                Text(
                  isPrivacy ? '••••••••' : CurrencyFormatter.format(reserved),
                  style: RiveroTypography.financialLarge,
                ),
                Text(
                  '${live.length} active',
                  style: RiveroTypography.bodySmall,
                ),
              ],
            ),
          ),
          const _Suggestions(),
          const SizedBox(height: RiveroSpacing.xl),
          if (mandates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(RiveroSpacing.xl),
              child: Center(
                child: Text(
                  'No mandates yet. Add one, or they appear when a bank '
                  'notification announces an autopay.',
                  textAlign: TextAlign.center,
                  style: RiveroTypography.bodyMedium,
                ),
              ),
            ),
          ...live.map((m) => _MandateTile(m, isPrivacy: isPrivacy)),
          if (inactive.isNotEmpty) ...[
            const SizedBox(height: RiveroSpacing.lg),
            Text(
              'PAUSED & ENDED',
              style: RiveroTypography.labelSmall.copyWith(letterSpacing: 1.5),
            ),
            const SizedBox(height: RiveroSpacing.sm),
            ...inactive.map((m) => _MandateTile(m, isPrivacy: isPrivacy)),
          ],
        ],
      ),
    );
  }
}

/// Icon and colour for each kind of autopay, so a SIP never looks like a
/// subscription.
({IconData icon, Color color}) mandateKindStyle(MandateKind k) => switch (k) {
  MandateKind.sip => (
    icon: Icons.trending_up_rounded,
    color: RiveroColors.investmentAccent,
  ),
  MandateKind.subscription => (
    icon: Icons.play_circle_outline_rounded,
    color: RiveroColors.mandateWarning,
  ),
  MandateKind.emi => (
    icon: Icons.account_balance_outlined,
    color: RiveroColors.liabilityAccent,
  ),
  MandateKind.insurance => (
    icon: Icons.health_and_safety_outlined,
    color: RiveroColors.savingsAccent,
  ),
  MandateKind.utility => (
    icon: Icons.bolt_rounded,
    color: RiveroColors.salaryAccent,
  ),
  MandateKind.rent => (
    icon: Icons.home_outlined,
    color: RiveroColors.walletAccent,
  ),
  MandateKind.other => (
    icon: Icons.autorenew_rounded,
    color: RiveroColors.expenseAccent,
  ),
};

/// The kind's icon on a tinted rounded square.
class MandateKindIcon extends StatelessWidget {
  const MandateKindIcon(this.kind, {super.key, this.size = 44});

  final MandateKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = mandateKindStyle(kind);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(s.icon, color: s.color, size: size * 0.55),
    );
  }
}

String _frequencyLabel(MandateFrequency f) => switch (f) {
  MandateFrequency.weekly => 'Weekly',
  MandateFrequency.monthly => 'Monthly',
  MandateFrequency.quarterly => 'Every 3 months',
  MandateFrequency.semiAnnual => 'Every 6 months',
  MandateFrequency.annual => 'Yearly',
  MandateFrequency.asPresented => 'When billed',
};

class _MandateTile extends ConsumerWidget {
  const _MandateTile(this.m, {required this.isPrivacy});

  final Mandate m;
  final bool isPrivacy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = m.nextExecutionDate;
    final now = DateTime.now();
    final ended =
        m.status != MandateStatus.active &&
        m.status != MandateStatus.registered;
    final kind = AutopayActions.kindOf(m);
    final style = mandateKindStyle(kind);
    final account = (ref.watch(activePhysicalAccountsProvider).value ?? [])
        .where((a) => a.id == m.physicalAccountId)
        .firstOrNull;
    final overdue = !ended && isOverdue(m, now);
    final short =
        account != null &&
        !account.isLiability &&
        account.balanceMinorUnits < mandateReserve(m);
    final when = ended
        ? (m.status == MandateStatus.paused ? 'Paused' : 'Ended')
        : due == null
        ? _frequencyLabel(m.frequency)
        : overdue
        ? 'Overdue since ${DateFormat('d MMM').format(due)}'
        : 'Next ${DateFormat('d MMM').format(due)} · '
              '${_frequencyLabel(m.frequency)}';
    final amount = isPrivacy
        ? '••••'
        : '${m.isVariableAmount ? 'up to ' : ''}'
              '${CurrencyFormatter.format(mandateReserve(m))}';

    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
      child: RiveroCard(
        key: ValueKey('mandate-${m.id}'),
        padding: const EdgeInsets.all(RiveroSpacing.md),
        onTap: () => _showActions(context, ref, overdue: overdue),
        child: Opacity(
          opacity: ended ? 0.55 : 1,
          child: Row(
            children: [
              MandateKindIcon(kind),
              const SizedBox(width: RiveroSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            m.payee,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RiveroTypography.titleMedium.copyWith(
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: RiveroSpacing.xs),
                        Container(
                          key: ValueKey('kind-${m.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: style.color.withValues(alpha: 0.16),
                            borderRadius: RiveroRadii.borderFull,
                          ),
                          child: Text(
                            kind.label,
                            style: RiveroTypography.labelSmall.copyWith(
                              color: style.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      when,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RiveroTypography.bodySmall.copyWith(
                        color: overdue ? RiveroColors.danger : null,
                      ),
                    ),
                    if (account != null)
                      Text(
                        overdue && short
                            ? '${account.name} is short: tap to say what happened'
                            : 'From ${account.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RiveroTypography.bodySmall.copyWith(
                          color: overdue && short ? RiveroColors.danger : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: RiveroSpacing.sm),
              Text(
                amount,
                style: RiveroTypography.monoMedium.copyWith(
                  color: RiveroColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(
    BuildContext context,
    WidgetRef ref, {
    required bool overdue,
  }) {
    final db = ref.read(databaseProvider);
    final dao = db.mandatesDao;
    final actions = AutopayActions(db);
    final paused = m.status == MandateStatus.paused;
    final due = m.nextExecutionDate;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RiveroColors.surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (overdue && due != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    RiveroSpacing.lg,
                    RiveroSpacing.lg,
                    RiveroSpacing.lg,
                    RiveroSpacing.xs,
                  ),
                  child: Text(
                    'Was due ${DateFormat('d MMM').format(due)} and Rivero '
                    'has not seen it. It is still kept aside in Safe to '
                    'spend. What happened?',
                    style: RiveroTypography.bodySmall,
                  ),
                ),
                ListTile(
                  key: const ValueKey('autopay-paid'),
                  leading: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: RiveroColors.success,
                  ),
                  title: const Text('It was paid'),
                  subtitle: const Text(
                    'Records the debit on its date and moves to the next one',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    actions.markPaid(m);
                  },
                ),
                ListTile(
                  key: const ValueKey('autopay-failed'),
                  leading: const Icon(
                    Icons.replay_rounded,
                    color: RiveroColors.warning,
                  ),
                  title: const Text('It failed: pay or retry later'),
                  subtitle: const Text(
                    'Keeps it aside until the date you pick',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      helpText: 'When will it be paid?',
                      initialDate: now.add(const Duration(days: 1)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 60)),
                    );
                    if (d != null) await actions.retryOn(m, d);
                  },
                ),
                ListTile(
                  key: const ValueKey('autopay-skip'),
                  leading: const Icon(Icons.skip_next_rounded),
                  title: const Text('Skip this one'),
                  subtitle: const Text(
                    'Not taken this time: nothing is recorded',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    actions.skip(m);
                  },
                ),
                const Divider(),
              ],
              ListTile(
                key: const ValueKey('autopay-edit'),
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(ctx);
                  _MandateSheet.show(context, existing: m);
                },
              ),
              ListTile(
                leading: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                ),
                title: Text(paused ? 'Mark as active' : 'Mark as paused'),
                onTap: () {
                  dao.updateMandateStatus(
                    m.id,
                    paused ? MandateStatus.active : MandateStatus.paused,
                  );
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.block_rounded,
                  color: RiveroColors.danger,
                ),
                title: const Text('I cancelled this in my bank'),
                subtitle: const Text('Stops reserving it from Safe-to-Spend'),
                onTap: () {
                  dao.updateMandateStatus(m.id, MandateStatus.cancelled);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add or edit an autopay: what it is for, payee, amount, how often, which
/// account, and the next date.
class _MandateSheet extends ConsumerStatefulWidget {
  const _MandateSheet({this.existing});

  final Mandate? existing;

  static Future<void> show(BuildContext context, {Mandate? existing}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: RiveroColors.surface,
        builder: (_) => _MandateSheet(existing: existing),
      );

  @override
  ConsumerState<_MandateSheet> createState() => _MandateSheetState();
}

class _MandateSheetState extends ConsumerState<_MandateSheet> {
  late final Mandate? _m = widget.existing;
  late final _payee = TextEditingController(text: _m?.payee);
  late final _amount = TextEditingController(
    text: _m == null ? '' : _rupees(mandateReserve(_m)),
  );
  late DateTime _next =
      _m?.nextExecutionDate ?? DateTime.now().add(const Duration(days: 7));
  late String? _accountId = _m?.physicalAccountId;
  late bool _variable = _m?.isVariableAmount ?? false;
  late MandateFrequency _frequency = _m?.frequency ?? MandateFrequency.monthly;
  late MandateKind _kind = _m == null
      ? MandateKind.other
      : AutopayActions.kindOf(_m);

  static String _rupees(int minor) => minor % 100 == 0
      ? '${minor ~/ 100}'
      : '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _payee.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(List<PhysicalAccount> accounts) async {
    final minor = parseAmountMinorUnits(_amount.text.trim());
    final accountId = _accountId ?? accounts.firstOrNull?.id;
    if (_payee.text.trim().isEmpty || minor <= 0 || accountId == null) {
      return;
    }
    final now = DateTime.now();
    final m = _m;
    await ref
        .read(databaseProvider)
        .mandatesDao
        .upsertMandate(
          MandatesCompanion(
            id: Value(m?.id ?? const Uuid().v4()),
            payee: Value(_payee.text.trim()),
            amountMinorUnits: Value(minor),
            isVariableAmount: Value(_variable),
            maxCapMinorUnits: Value(_variable ? minor : null),
            frequency: Value(_frequency),
            kind: Value(_kind),
            physicalAccountId: Value(accountId),
            allocationBucketId: Value(m?.allocationBucketId),
            startDate: Value(m?.startDate ?? now),
            endDate: Value(m?.endDate),
            nextExecutionDate: Value(_next),
            status: Value(m?.status ?? MandateStatus.active),
            mandateUmn: Value(m?.mandateUmn),
            createdAt: Value(m?.createdAt ?? now),
            updatedAt: Value(now),
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Autopay can be taken from a bank account or charged to a card.
    final accounts = (ref.watch(activePhysicalAccountsProvider).value ?? [])
        .where(
          (a) =>
              !a.isLiability ||
              !StandardAccountTypes.isLongTermDebt(a.accountType),
        )
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
              _m == null ? 'New autopay' : 'Edit autopay',
              style: RiveroTypography.titleLarge,
            ),
            const SizedBox(height: RiveroSpacing.md),
            Text('What is it for?', style: RiveroTypography.bodySmall),
            const SizedBox(height: RiveroSpacing.xs),
            Wrap(
              spacing: RiveroSpacing.sm,
              runSpacing: RiveroSpacing.xs,
              children: [
                for (final k in MandateKind.values)
                  ChoiceChip(
                    key: ValueKey('kind-chip-${k.name}'),
                    avatar: Icon(
                      mandateKindStyle(k).icon,
                      size: 16,
                      color: mandateKindStyle(k).color,
                    ),
                    label: Text(k.label),
                    selected: _kind == k,
                    showCheckmark: false,
                    shape: const StadiumBorder(),
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: RiveroSpacing.sm),
            TextField(
              key: const ValueKey('autopay-payee'),
              controller: _payee,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Payee (e.g. Netflix, Axis Bluechip SIP)',
              ),
              onChanged: (v) {
                // Suggest the kind from the name until the user picks one.
                if (_m == null) {
                  setState(() => _kind = MandateKind.guess(v));
                }
              },
            ),
            TextField(
              key: const ValueKey('autopay-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Amount varies (amount is the cap)'),
              value: _variable,
              onChanged: (v) => setState(() => _variable = v),
            ),
            PickerField<MandateFrequency>(
              label: 'How often',
              value: _frequency,
              options: [
                for (final f in MandateFrequency.values)
                  PickerOption(f, _frequencyLabel(f)),
              ],
              onChanged: (v) => setState(() => _frequency = v),
            ),
            const SizedBox(height: RiveroSpacing.sm),
            if (accounts.isNotEmpty)
              PickerField<String>(
                label: 'Taken from',
                value: accounts.any((a) => a.id == _accountId)
                    ? _accountId
                    : accounts.first.id,
                options: [for (final a in accounts) PickerOption(a.id, a.name)],
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Next debit · ${DateFormat('d MMM y').format(_next)}',
              ),
              trailing: const Icon(Icons.calendar_today_rounded, size: 18),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _next,
                  firstDate: _next.isBefore(now) ? _next : now,
                  lastDate: now.add(const Duration(days: 730)),
                );
                if (d != null) setState(() => _next = d);
              },
            ),
            const SizedBox(height: RiveroSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('autopay-save'),
                onPressed: () => _save(accounts),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Payments that repeat like a subscription but are not an autopay yet.
final AutoDisposeFutureProvider<List<RecurringSuggestion>>
subscriptionSuggestionsProvider = FutureProvider.autoDispose((ref) {
  ref
    ..watch(allMandatesProvider) // re-check after one is added
    ..watch(allTransactionsStreamProvider);
  return SubscriptionFinder(ref.watch(databaseProvider)).find();
});

class _Suggestions extends ConsumerWidget {
  const _Suggestions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(subscriptionSuggestionsProvider).value ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final privacy = ref.watch(privacyModeProvider);
    final finder = SubscriptionFinder(ref.read(databaseProvider));
    return Padding(
      padding: const EdgeInsets.only(top: RiveroSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LOOKS LIKE AUTOPAY',
            style: RiveroTypography.labelSmall.copyWith(letterSpacing: 1.5),
          ),
          const SizedBox(height: RiveroSpacing.sm),
          for (final s in list)
            Padding(
              key: ValueKey('suggest-${s.merchant}'),
              padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
              child: RiveroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.merchant} · '
                      '${privacy ? '₹••••' : CurrencyFormatter.format(s.amountMinorUnits)} '
                      '${s.frequency == MandateFrequency.weekly ? 'weekly' : 'monthly'}',
                      style: RiveroTypography.titleMedium,
                    ),
                    Text(
                      'Paid ${s.count} times at a regular interval. Next '
                      'around ${DateFormat('d MMM').format(s.next)}. Add it '
                      'so Safe to spend keeps it aside?',
                      style: RiveroTypography.bodySmall,
                    ),
                    const SizedBox(height: RiveroSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: ValueKey('suggest-no-${s.merchant}'),
                            onPressed: () async {
                              await finder.dismiss(s);
                              ref.invalidate(subscriptionSuggestionsProvider);
                            },
                            style: OutlinedButton.styleFrom(
                              shape: const StadiumBorder(),
                            ),
                            child: const Text('Not autopay'),
                          ),
                        ),
                        const SizedBox(width: RiveroSpacing.sm),
                        Expanded(
                          child: FilledButton(
                            key: ValueKey('suggest-add-${s.merchant}'),
                            onPressed: () => finder.accept(s),
                            style: FilledButton.styleFrom(
                              shape: const StadiumBorder(),
                            ),
                            child: const Text('Add autopay'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
