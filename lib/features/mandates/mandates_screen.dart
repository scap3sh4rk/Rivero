import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/mandates/subscription_finder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
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
        onPressed: () => _AddMandateSheet.show(context),
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

class _MandateTile extends ConsumerWidget {
  const _MandateTile(this.m, {required this.isPrivacy});

  final Mandate m;
  final bool isPrivacy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = m.nextExecutionDate;
    final ended =
        m.status != MandateStatus.active &&
        m.status != MandateStatus.registered;
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
      child: RiveroCard(
        padding: const EdgeInsets.all(RiveroSpacing.md),
        onTap: () => _showActions(context, ref),
        child: Opacity(
          opacity: ended ? 0.55 : 1,
          child: Row(
            children: [
              BankBadge(name: m.payee),
              const SizedBox(width: RiveroSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.payee,
                      style: RiveroTypography.titleMedium.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      ended
                          ? m.status.name
                          : due == null
                          ? m.frequency.name
                          : isOverdue(m, DateTime.now())
                          ? 'Overdue since ${DateFormat('d MMM').format(due)}'
                                ' · not seen yet'
                          : 'Next ${DateFormat('d MMM').format(due)}'
                                ' · ${m.frequency.name}',
                      style: RiveroTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                isPrivacy
                    ? '••••'
                    : '${m.isVariableAmount ? 'up to ' : ''}'
                          '${CurrencyFormatter.format(m.isVariableAmount ? (m.maxCapMinorUnits ?? m.amountMinorUnits) : m.amountMinorUnits)}',
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

  void _showActions(BuildContext context, WidgetRef ref) {
    final dao = ref.read(databaseProvider).mandatesDao;
    final paused = m.status == MandateStatus.paused;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RiveroColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    );
  }
}

class _AddMandateSheet extends ConsumerStatefulWidget {
  const _AddMandateSheet();

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RiveroColors.surface,
    builder: (_) => const _AddMandateSheet(),
  );

  @override
  ConsumerState<_AddMandateSheet> createState() => _AddMandateSheetState();
}

class _AddMandateSheetState extends ConsumerState<_AddMandateSheet> {
  final _payee = TextEditingController();
  final _amount = TextEditingController();
  DateTime _next = DateTime.now().add(const Duration(days: 7));
  String? _accountId;
  bool _variable = false;

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
    await ref
        .read(databaseProvider)
        .mandatesDao
        .upsertMandate(
          MandatesCompanion(
            id: Value(const Uuid().v4()),
            payee: Value(_payee.text.trim()),
            amountMinorUnits: Value(minor),
            isVariableAmount: Value(_variable),
            maxCapMinorUnits: Value(_variable ? minor : null),
            frequency: const Value(MandateFrequency.monthly),
            physicalAccountId: Value(accountId),
            startDate: Value(now),
            nextExecutionDate: Value(_next),
            status: const Value(MandateStatus.active),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    if (mounted) Navigator.pop(context);
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
          Text('New mandate', style: RiveroTypography.titleLarge),
          const SizedBox(height: RiveroSpacing.lg),
          TextField(
            controller: _payee,
            decoration: const InputDecoration(
              labelText: 'Payee (e.g. Netflix)',
            ),
          ),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (₹)'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Amount varies (amount is the cap)'),
            value: _variable,
            onChanged: (v) => setState(() => _variable = v),
          ),
          if (accounts.isNotEmpty)
            PickerField<String>(
              label: 'Debited from',
              value: _accountId ?? accounts.first.id,
              options: [for (final a in accounts) PickerOption(a.id, a.name)],
              onChanged: (v) => setState(() => _accountId = v),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Next debit · ${DateFormat('d MMM y').format(_next)}'),
            trailing: const Icon(Icons.calendar_today_rounded, size: 18),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _next,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 730)),
              );
              if (d != null) setState(() => _next = d);
            },
          ),
          const SizedBox(height: RiveroSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _save(accounts),
              child: const Text('Save'),
            ),
          ),
        ],
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
