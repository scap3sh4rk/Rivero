import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/currency/currency.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/card_cycle.dart';
import 'package:rivero/core/domain/credit_utilization.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/account_color.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/rivero_fab.dart';
import 'package:rivero/features/accounts/screens/account_detail_screen.dart';
import 'package:rivero/features/accounts/widgets/create_account_sheet.dart';
import 'package:rivero/features/settings/screens/exchange_rates_screen.dart';

/// Accounts: net worth, then bank & cash and cards as short rows.
/// Long-press a row to drag it up or down; tap to open it.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts =
        ref.watch(activePhysicalAccountsProvider).value ?? const [];
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final banks = accounts.where((a) => !a.isLiability).toList();
    final cards = accounts.where((a) => a.isLiability).toList();
    // Totals in rupees (other currencies at the user's rate).
    final rates = ref.watch(exchangeRatesProvider);
    final bankTotal = rates
        .inHome(banks)
        .fold<int>(0, (s, a) => s + a.balanceMinorUnits);
    final bills = CardBills.of(rates.inHome(accounts));
    final debt = rates
        .inHome(cards)
        .fold<int>(
          0,
          (s, a) => s + (a.balanceMinorUnits < 0 ? -a.balanceMinorUnits : 0),
        );

    Future<void> reorder(List<PhysicalAccount> group, int from, int to) async {
      final ids = group.map((a) => a.id).toList();
      final moved = ids.removeAt(from);
      ids.insert(to > from ? to - 1 : to, moved);
      // Keep the other group's positions after this one's.
      final others = accounts
          .where((a) => !ids.contains(a.id))
          .map((a) => a.id);
      final dao = ref.read(databaseProvider).accountsDao;
      await dao.reorderAccounts(
        group.first.isLiability ? [...others, ...ids] : [...ids, ...others],
      );
    }

    Widget section(String title, List<PhysicalAccount> group) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: RiveroSpacing.xl,
            bottom: RiveroSpacing.sm,
          ),
          child: Text(title, style: RiveroTypography.titleMedium),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, _, _) => Material(
            color: Colors.transparent,
            elevation: 6,
            borderRadius: RiveroRadii.borderLg,
            child: child,
          ),
          onReorderStart: (_) => HapticFeedback.mediumImpact(),
          onReorder: (from, to) => reorder(group, from, to),
          children: [
            for (var i = 0; i < group.length; i++)
              ReorderableDelayedDragStartListener(
                key: ValueKey(group[i].id),
                index: i,
                child: _AccountRow(
                  group[i],
                  afford: bills.byCard[group[i].id],
                  payer: bills.payerOf[group[i].id],
                  paysFor: [
                    for (final e in bills.payerOf.entries)
                      if (e.value.id == group[i].id)
                        cards.firstWhere((c) => c.id == e.key).name,
                  ],
                ),
              ),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: const RiveroAppBar(title: 'Accounts'),
      floatingActionButton: RiveroFab(
        tooltip: 'Add account or card',
        onPressed: () => CreateAccountSheet.show(context),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge + 72 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          RiveroCard(
            key: const ValueKey('networth-card'),
            onTap: () => NetWorthSheet.show(context),
            isElevated: true,
            padding: const EdgeInsets.all(RiveroSpacing.xl),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Net worth', style: RiveroTypography.bodyMedium),
                      Text(
                        money(bankTotal - debt),
                        style: RiveroTypography.financialLarge.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Bank ${money(bankTotal)}'
                        '${cards.isEmpty ? '' : ' · Cards −${money(debt)}'}',
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
          for (final c in foreignCurrencies(accounts))
            if (!rates.has(c))
              Padding(
                key: ValueKey('no-rate-$c'),
                padding: const EdgeInsets.only(bottom: RiveroSpacing.md),
                child: InkWell(
                  onTap: () => ExchangeRatesScreen.open(context),
                  child: Text(
                    'Set a rate for $c (Settings → Exchange rates): until '
                    'then it is left out of the totals.',
                    style: RiveroTypography.bodySmall.copyWith(
                      color: RiveroColors.warning,
                    ),
                  ),
                ),
              ),
          if (banks.isNotEmpty) section('Bank & cash', banks),
          if (cards.isNotEmpty) _CardsSummary(afford: bills.all, money: money),
          if (cards.isNotEmpty) section('Cards', cards),
          if (accounts.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: RiveroSpacing.md),
              child: Center(
                child: Text(
                  'Long-press an account to reorder',
                  style: RiveroTypography.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A bank/cash account or a credit card, with what matters for each.
class _AccountRow extends ConsumerWidget {
  const _AccountRow(this.a, {this.afford, this.payer, this.paysFor = const []});

  final PhysicalAccount a;

  /// Cards whose bills this account pays.
  final List<String> paysFor;

  /// Can this card's bill be paid (see CardBills); null for a loan.
  final CardAffordability? afford;

  /// The account the bill is paid from, when one is set.
  final PhysicalAccount? payer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tint = accountColor(a);
    final money = ref.watch(accountMoneyMaskProvider)(a.id);
    final hidden = ref.watch(hiddenBalancesProvider).contains(a.id);
    // Hide or show this one account's money (saved).
    final eye = IconButton(
      key: ValueKey('hide-${a.id}'),
      tooltip: hidden ? 'Show balance' : 'Hide balance',
      visualDensity: VisualDensity.compact,
      onPressed: () {
        HapticFeedback.selectionClick();
        final n = ref.read(hiddenBalancesProvider.notifier);
        n.state = hidden ? ({...n.state}..remove(a.id)) : {...n.state, a.id};
      },
      icon: Icon(
        hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 20,
        color: RiveroColors.textMuted,
      ),
    );
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BankBadge(
          name: a.institution,
          color: tint,
          imagePath: a.imagePath,
          size: 52,
        ),
        const SizedBox(width: RiveroSpacing.md),
        Expanded(child: _identity()),
        eye,
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.md),
      child: RiveroCard(
        padding: const EdgeInsets.all(RiveroSpacing.xl),
        onTap: () => AccountDetailScreen.open(context, a.id),
        child: a.isLiability
            ? _cardBody(header, money)
            : _bankBody(header, money),
      ),
    );
  }

  /// Bank, wallet or cash: name and digits in full, a large balance, and
  /// what the balance is (when it was last confirmed, which card bills it
  /// pays).
  Widget _bankBody(Widget header, String Function(int) money) {
    final asOf = a.balanceAsOf;
    final notes = [
      if (asOf != null)
        'Balance confirmed ${DateFormat('d MMM, h:mm a').format(asOf)}',
      if (paysFor.isNotEmpty) 'Pays the ${paysFor.join(', ')} bill',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: RiveroSpacing.lg),
        Text('Balance', style: RiveroTypography.bodySmall),
        Text(
          accountMoney(a, a.balanceMinorUnits, money),
          key: ValueKey('balance-${a.id}'),
          style: RiveroTypography.financialLarge,
        ),
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(top: RiveroSpacing.xs),
            child: Text(n, style: RiveroTypography.bodySmall),
          ),
      ],
    );
  }

  /// Name, then bank ••mask · type: which account this is at a glance.
  Widget _identity() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        a.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: RiveroTypography.titleMedium,
      ),
      const SizedBox(height: 2),
      Text(
        '${a.institution} ••${a.accountMask} · ${a.accountType}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: RiveroTypography.bodySmall,
      ),
    ],
  );

  /// Billing cycle: days left until the statement, the due date, and whether
  /// the money you hold covers the bill.
  List<Widget> _cycleSection(int owed, String Function(int) money) {
    final cycle = CardCycle.of(
      statementDay: a.statementDay,
      paymentDueDay: a.paymentDueDay,
      now: DateTime.now(),
    );
    if (cycle == null) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: RiveroSpacing.sm),
          child: Text(
            'Add the statement and due days to track the billing cycle',
            key: ValueKey('no-cycle-${a.id}'),
            style: RiveroTypography.bodySmall,
          ),
        ),
      ];
    }
    final afford = this.afford;
    final due = DateFormat('d MMM').format(cycle.dueDate);
    final from = payer == null ? '' : ' from ${payer!.name}';
    final color = owed == 0 || afford == null
        ? RiveroColors.textSecondary
        : afford.canPay
        ? RiveroColors.success
        : RiveroColors.danger;
    return [
      const SizedBox(height: RiveroSpacing.md),
      ClipRRect(
        borderRadius: RiveroRadii.borderFull,
        child: LinearProgressIndicator(
          key: ValueKey('cycle-${a.id}'),
          value: cycle.progress,
          minHeight: 4,
          backgroundColor: RiveroColors.surfaceInteractive,
          valueColor: AlwaysStoppedAnimation<Color>(RiveroColors.accent),
        ),
      ),
      const SizedBox(height: RiveroSpacing.xs),
      Row(
        children: [
          Expanded(
            child: Text(
              cycle.daysToStatement == 0
                  ? 'Statement today'
                  : '${cycle.daysToStatement} days left in this billing cycle',
              key: ValueKey('cycle-days-${a.id}'),
              style: RiveroTypography.bodySmall,
            ),
          ),
          Text(
            'Pay by $due · ${cycle.daysToDue == 0 ? 'today' : '${cycle.daysToDue} days'}',
            key: ValueKey('due-${a.id}'),
            style: RiveroTypography.bodySmall,
          ),
        ],
      ),
      if (owed > 0 && afford != null)
        Padding(
          padding: const EdgeInsets.only(top: RiveroSpacing.xs),
          child: Text(
            afford.canPay
                ? 'You can pay this$from: ${money(afford.leftAfter)} left after'
                : 'Short by ${money(afford.shortBy)} to pay this$from',
            key: ValueKey('afford-${a.id}'),
            style: RiveroTypography.labelLarge.copyWith(color: color),
          ),
        ),
    ];
  }

  Widget _cardBody(Widget header, String Function(int) money) {
    final u = CreditUtilization.fromBalance(
      creditLimitMinorUnits: a.creditLimitMinorUnits,
      balanceMinorUnits: a.balanceMinorUnits,
    );
    final hasLimit = u.creditLimitMinorUnits > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: RiveroSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Outstanding', style: RiveroTypography.bodySmall),
                  Text(
                    money(u.usedMinorUnits),
                    style: RiveroTypography.financialMedium,
                  ),
                ],
              ),
            ),
            if (hasLimit)
              Container(
                key: ValueKey('usage-${a.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: RiveroSpacing.md,
                  vertical: RiveroSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: u.statusColor.withValues(alpha: 0.15),
                  borderRadius: RiveroRadii.borderFull,
                  border: Border.all(
                    color: u.statusColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  u.pillLabel,
                  style: RiveroTypography.labelLarge.copyWith(
                    color: u.statusColor,
                  ),
                ),
              ),
          ],
        ),
        ..._cycleSection(u.usedMinorUnits, money),
        if (hasLimit) ...[
          const SizedBox(height: RiveroSpacing.md),
          _UsageBar(percent: u.utilizationPercent, color: u.statusColor),
          const SizedBox(height: RiveroSpacing.sm),
          Text(
            'Limit ${money(u.creditLimitMinorUnits)} · '
            'Available ${money(u.availableMinorUnits)}',
            style: RiveroTypography.bodySmall,
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: RiveroSpacing.sm),
            child: Text(
              'Add the card limit to see usage',
              style: RiveroTypography.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Usage bar with ticks at 10% and 30%, the two lines that matter.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.percent, required this.color});

  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        height: 10,
        child: Stack(
          children: [
            Positioned.fill(
              top: 2,
              bottom: 2,
              child: ClipRRect(
                borderRadius: RiveroRadii.borderFull,
                child: LinearProgressIndicator(
                  value: (percent / 100).clamp(0.0, 1.0),
                  backgroundColor: RiveroColors.surfaceInteractive,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            for (final mark in [0.10, 0.30])
              Positioned(
                left: c.maxWidth * mark - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: RiveroColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// All cards together: what they owe against what you hold.
class _CardsSummary extends StatelessWidget {
  const _CardsSummary({required this.afford, required this.money});

  final CardAffordability afford;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) {
    final a = afford;
    if (a.owed == 0) return const SizedBox.shrink();
    final color = a.canPay ? RiveroColors.success : RiveroColors.danger;
    return Padding(
      padding: const EdgeInsets.only(top: RiveroSpacing.lg),
      child: RiveroCard(
        key: const ValueKey('cards-summary'),
        child: Row(
          children: [
            Icon(
              a.canPay ? Icons.check_circle_rounded : Icons.warning_rounded,
              color: color,
            ),
            const SizedBox(width: RiveroSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cards owe ${money(a.owed)}',
                    style: RiveroTypography.bodyLarge,
                  ),
                  Text(
                    // Each card from its own account where one is set,
                    // the rest from your other accounts (see CardBills).
                    a.canPay
                        ? 'You can pay every card'
                        : 'Short by ${money(a.shortBy)} to pay every card',
                    style: RiveroTypography.bodySmall.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
