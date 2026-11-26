import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/currency/currency.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_group.dart';
import 'package:rivero/core/domain/card_cycle.dart';
import 'package:rivero/core/domain/credit_utilization.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/look.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/account_color.dart';
import 'package:rivero/design_system/widgets/balance_mask.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/rivero_fab.dart';
import 'package:rivero/features/accounts/screens/account_detail_screen.dart';
import 'package:rivero/features/accounts/widgets/bill_status.dart';
import 'package:rivero/features/accounts/widgets/create_account_sheet.dart';
import 'package:rivero/features/settings/screens/exchange_rates_screen.dart';

/// Accounts: net worth, then one section per kind of account (bank & cash,
/// investments, fixed deposits, cards, loans) in the user's order. Tap a
/// section's name to fold it; long-press an account to drag it.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts =
        ref.watch(activePhysicalAccountsProvider).value ?? const [];
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final prefs = ref.watch(accountGroupPrefsProvider);
    final cards = accounts.where((a) => a.isLiability).toList();
    // Totals in rupees (other currencies at the user's rate).
    final rates = ref.watch(exchangeRatesProvider);
    final home = rates.inHome(accounts);
    int owedOn(PhysicalAccount a) =>
        a.balanceMinorUnits < 0 ? -a.balanceMinorUnits : 0;
    // Net worth counts only the accounts the user keeps in it.
    final counted = home.where((a) => a.includeInNetWorth);
    final assets = counted
        .where((a) => !a.isLiability)
        .fold<int>(0, (s, a) => s + a.balanceMinorUnits);
    final debt = counted
        .where((a) => a.isLiability)
        .fold<int>(0, (s, a) => s + owedOn(a));
    // Each card's bill is what its last statement asks for (spends since
    // go on the next one).
    final cardBills = ref.watch(cardBillsProvider);
    final bills = CardBills.of(home, due: cardBills);
    final groups = {
      for (final g in AccountGroup.values)
        g: [
          for (final a in accounts)
            if (AccountGroup.of(a) == g) a,
        ],
    };

    Future<void> reorder(List<PhysicalAccount> group, int from, int to) async {
      final ids = group.map((a) => a.id).toList();
      final moved = ids.removeAt(from);
      ids.insert(to > from ? to - 1 : to, moved);
      // Every section in its shown order, this one with its new order.
      final all = [
        for (final g in prefs.order)
          if (groups[g]!.any((a) => a.id == group.first.id))
            ...ids
          else
            ...groups[g]!.map((a) => a.id),
      ];
      await ref.read(databaseProvider).accountsDao.reorderAccounts(all);
    }

    Widget section(AccountGroup g) {
      final group = groups[g]!;
      final folded = prefs.collapsed.contains(g);
      return Column(
        key: ValueKey('section-${g.name}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: ValueKey('fold-${g.name}'),
            borderRadius: RiveroRadii.borderLg,
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(accountGroupPrefsProvider.notifier).state = prefs
                  .toggled(g);
            },
            child: Padding(
              padding: const EdgeInsets.only(
                top: RiveroSpacing.xl,
                bottom: RiveroSpacing.sm,
              ),
              child: Row(
                children: [
                  Text(g.label, style: RiveroTypography.titleMedium),
                  const SizedBox(width: RiveroSpacing.xs),
                  AnimatedRotation(
                    turns: folded ? -0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 22,
                      color: RiveroColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  // Only how many: a total here would show money the
                  // accounts' own eyes hide.
                  Text(
                    group.length == 1
                        ? '1 account'
                        : '${group.length} accounts',
                    key: ValueKey('section-count-${g.name}'),
                    style: RiveroTypography.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (!folded) ...[
            if (g == AccountGroup.card)
              _CardsSummary(afford: bills.all, money: money),
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
                      bills: bills,
                      bill: cardBills[group[i].id],
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
        ],
      );
    }

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Accounts',
        actions: [
          IconButton(
            key: const ValueKey('arrange-sections'),
            tooltip: 'Arrange sections',
            icon: Icon(
              Icons.swap_vert_rounded,
              color: RiveroColors.textSecondary,
            ),
            onPressed: () => _ArrangeSheet.show(context, [
              for (final g in prefs.order)
                if (groups[g]!.isNotEmpty) g,
            ]),
          ),
        ],
      ),
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
          if (ref.watch(showNetWorthProvider))
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
                          money(assets - debt),
                          style: RiveroTypography.financialLarge.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Assets ${money(assets)}'
                          '${debt == 0 ? '' : ' · Owed −${money(debt)}'}'
                          '${counted.length < accounts.length ? ' · ${accounts.length - counted.length} left out' : ''}',
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
                padding: const EdgeInsets.only(top: RiveroSpacing.md),
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
          for (final g in prefs.order)
            if (groups[g]!.isNotEmpty) section(g),
          if (accounts.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: RiveroSpacing.md),
              child: Center(
                child: Text(
                  'Tap a section to fold it · long-press an account to move it',
                  style: RiveroTypography.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Drag the sections into the order you want them on Accounts.
class _ArrangeSheet extends ConsumerStatefulWidget {
  const _ArrangeSheet(this.shown);

  final List<AccountGroup> shown;

  static Future<void> show(BuildContext context, List<AccountGroup> shown) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: RiveroColors.surface,
        builder: (_) => _ArrangeSheet(shown),
      );

  @override
  ConsumerState<_ArrangeSheet> createState() => _ArrangeSheetState();
}

class _ArrangeSheetState extends ConsumerState<_ArrangeSheet> {
  late final List<AccountGroup> _order = [
    ...ref.read(accountGroupPrefsProvider).order,
  ];

  void _move(int from, int to) {
    setState(() {
      final g = _order.removeAt(from);
      _order.insert(to > from ? to - 1 : to, g);
    });
    final n = ref.read(accountGroupPrefsProvider.notifier);
    n.state = n.state.reordered([..._order]);
  }

  @override
  Widget build(BuildContext context) {
    // Every section can be placed, also ones with no accounts yet.
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RiveroSpacing.xl,
              RiveroSpacing.xl,
              RiveroSpacing.xl,
              RiveroSpacing.sm,
            ),
            child: Text('Arrange sections', style: RiveroTypography.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.xl),
            child: Text(
              'Drag to reorder. Sections with no accounts are not shown.',
              style: RiveroTypography.bodySmall,
            ),
          ),
          ReorderableListView(
            shrinkWrap: true,
            onReorder: _move,
            children: [
              for (final g in _order)
                ListTile(
                  key: ValueKey('arrange-${g.name}'),
                  title: Text(g.label),
                  subtitle: widget.shown.contains(g)
                      ? null
                      : const Text('No accounts yet'),
                  trailing: const Icon(Icons.drag_handle_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A bank/cash account or a credit card, with what matters for each.
class _AccountRow extends ConsumerWidget {
  const _AccountRow(this.a, {this.bills, this.bill, this.paysFor = const []});

  final PhysicalAccount a;

  /// Cards whose bills this account pays.
  final List<String> paysFor;

  /// Every card's bill (see CardBills); a loan has no entry.
  final CardBills? bills;

  /// This card's bill: what its last statement still asks for.
  final CardBill? bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tint = accountColor(a);
    final money = ref.watch(accountMoneyMaskProvider)(a.id);
    // Card size picked in Settings > Appearance (bank & cash, and cards).
    final look = ref.watch(lookProvider);
    final size = a.isLiability ? look.creditCards : look.bankCards;
    final hidden = accountMasked(ref, a.id);
    // Hide or show this one account's money (saved).
    final eye = IconButton(
      key: ValueKey('hide-${a.id}'),
      tooltip: hidden ? 'Show balance' : 'Hide balance',
      visualDensity: VisualDensity.compact,
      onPressed: () {
        HapticFeedback.selectionClick();
        toggleAccountMask(ref, a.id);
      },
      icon: Icon(
        hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 20,
        color: RiveroColors.textMuted,
      ),
    );
    final badge = BankBadge(
      name: a.institution,
      color: tint,
      imagePath: a.imagePath,
      size: switch (size) {
        CardSize.compact => 40,
        CardSize.standard => 48,
        CardSize.large => 52,
      },
    );
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        badge,
        const SizedBox(width: RiveroSpacing.md),
        Expanded(child: _identity(lines: size == CardSize.compact ? 1 : 2)),
        eye,
      ],
    );
    return Padding(
      padding: EdgeInsets.only(
        bottom: size == CardSize.compact ? RiveroSpacing.sm : RiveroSpacing.md,
      ),
      child: RiveroCard(
        padding: EdgeInsets.all(switch (size) {
          CardSize.compact => RiveroSpacing.md,
          CardSize.standard => RiveroSpacing.lg,
          CardSize.large => RiveroSpacing.xl,
        }),
        onTap: () => AccountDetailScreen.open(context, a.id),
        child: a.isLiability
            ? _cardBody(header, money, size)
            : AccountGroup.isFixedDeposit(a)
            ? _fdBody(header, money)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (size == CardSize.large)
                    _bankBody(header, money)
                  else
                    _bankRow(badge, eye, money, size),
                  if (ref.watch(balanceToUpdateProvider).contains(a.id))
                    Padding(
                      padding: const EdgeInsets.only(top: RiveroSpacing.sm),
                      child: Text(
                        'Update the balance: a payment was more than Rivero '
                        'thought this account held',
                        key: ValueKey('update-balance-${a.id}'),
                        style: RiveroTypography.bodySmall.copyWith(
                          color: RiveroColors.warning,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// Compact and standard bank & cash cards: one row, the balance on the
  /// right. Standard lets the name and digits use two lines.
  Widget _bankRow(
    Widget badge,
    Widget eye,
    String Function(int) money,
    CardSize size,
  ) => Row(
    children: [
      badge,
      const SizedBox(width: RiveroSpacing.md),
      Expanded(child: _identity(lines: size == CardSize.compact ? 1 : 2)),
      const SizedBox(width: RiveroSpacing.sm),
      Text(
        accountMoney(a, a.balanceMinorUnits, money),
        key: ValueKey('balance-${a.id}'),
        style: size == CardSize.compact
            ? RiveroTypography.titleMedium
            : RiveroTypography.financialMedium,
      ),
      eye,
    ],
  );

  /// Large bank & cash cards: name and digits in full, a large balance, and
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

  /// Fixed deposits: what was put in, the rate, when it matures and what
  /// it will be worth then (interest compounded every quarter).
  Widget _fdBody(Widget header, String Function(int) money) {
    final now = DateTime.now();
    final maturity = a.fdMaturityDate;
    final days = maturity == null
        ? null
        : DateTime(
            maturity.year,
            maturity.month,
            maturity.day,
          ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final rate = a.fdRateBps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: RiveroSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Deposited', style: RiveroTypography.bodySmall),
                  Text(
                    accountMoney(a, a.balanceMinorUnits, money),
                    key: ValueKey('balance-${a.id}'),
                    style: RiveroTypography.financialMedium,
                  ),
                ],
              ),
            ),
            if (maturity != null && rate != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('At maturity', style: RiveroTypography.bodySmall),
                  Text(
                    accountMoney(a, FixedDeposit.maturityValue(a), money),
                    key: ValueKey('fd-maturity-${a.id}'),
                    style: RiveroTypography.financialMedium.copyWith(
                      color: RiveroColors.success,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: RiveroSpacing.xs),
        Text(
          [
            if (rate != null)
              '${rate ~/ 100}.${(rate % 100).toString().padLeft(2, '0')}% a year',
            if (maturity != null && days! <= 0)
              'Matured ${DateFormat('d MMM y').format(maturity)}'
            else if (maturity != null)
              'Matures ${DateFormat('d MMM y').format(maturity)} · in $days days',
            if (rate == null || maturity == null)
              'Edit to add the rate and maturity date',
          ].join(' · '),
          style: RiveroTypography.bodySmall.copyWith(
            color: days != null && days <= 0 ? RiveroColors.warning : null,
          ),
        ),
      ],
    );
  }

  /// Name, then bank ••mask · type: which account this is at a glance.
  Widget _identity({int lines = 2}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        a.name,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: RiveroTypography.titleMedium,
      ),
      const SizedBox(height: 2),
      Text(
        '${a.institution} ••${a.accountMask} · ${a.accountType}',
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: RiveroTypography.bodySmall,
      ),
    ],
  );

  /// Just whether the bill can be paid (compact cards).
  List<Widget> _affordLine(int owed, String Function(int) money) {
    final status = bills == null || (bill?.due ?? owed) == 0
        ? null
        : billStatus(bills!, a, money);
    if (status == null) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: RiveroSpacing.sm),
        child: Text(
          status.text,
          key: ValueKey('afford-${a.id}'),
          style: RiveroTypography.labelLarge.copyWith(
            color: status.ok ? RiveroColors.success : RiveroColors.danger,
          ),
        ),
      ),
    ];
  }

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
        ..._affordLine(owed, money),
      ];
    }
    final due = DateFormat('d MMM').format(cycle.dueDate);
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
            (bill?.due ?? owed) == 0
                ? 'Nothing due · statement ${DateFormat('d MMM').format(cycle.nextStatement)}'
                : bill?.overdueSince != null
                ? 'Pay ${money(bill!.due)} · overdue since '
                      '${DateFormat('d MMM').format(bill!.overdueSince!)}'
                : 'Pay ${money(bill?.due ?? owed)} by $due · '
                      '${cycle.daysToDue == 0 ? 'today' : '${cycle.daysToDue} days'}',
            key: ValueKey('due-${a.id}'),
            style: RiveroTypography.bodySmall,
          ),
        ],
      ),
      ..._affordLine(owed, money),
    ];
  }

  /// Credit cards: compact = outstanding, usage and whether you can pay;
  /// standard adds the billing cycle and limit; large shows it all bigger.
  Widget _cardBody(Widget header, String Function(int) money, CardSize size) {
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
                    style: size == CardSize.large
                        ? RiveroTypography.financialLarge
                        : RiveroTypography.financialMedium,
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
        if (size == CardSize.compact)
          ..._affordLine(u.usedMinorUnits, money)
        else
          ..._cycleSection(u.usedMinorUnits, money),
        if (size == CardSize.compact)
          const SizedBox.shrink()
        else if (hasLimit) ...[
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
    // Space above and below: it never touches the first card.
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.md),
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
