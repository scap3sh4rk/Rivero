import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/card_cycle.dart';
import 'package:rivero/core/mandates/autopay_actions.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/accounts/screens/account_detail_screen.dart';
import 'package:rivero/features/accounts/widgets/bill_status.dart';
import 'package:rivero/features/mandates/mandates_screen.dart';

/// What cards, loans and autopays need before payday (paise).
class CommitmentTotals {
  const CommitmentTotals({
    required this.cards,
    required this.loans,
    required this.autopay,
    required this.available,
  });

  factory CommitmentTotals.of(
    List<PhysicalAccount> accounts,
    List<Mandate> mandates,
    DateTime cycleEnd,
    DateTime now,
  ) {
    int owedOn(PhysicalAccount a) =>
        a.balanceMinorUnits < 0 ? -a.balanceMinorUnits : 0;
    final liabilities = accounts.where((a) => a.isLiability);
    final cards = liabilities
        .where((a) => a.creditLimitMinorUnits > 0)
        .fold<int>(0, (s, a) => s + owedOn(a));
    final loans = liabilities
        .where((a) => a.creditLimitMinorUnits <= 0)
        .fold<int>(0, (s, a) => s + owedOn(a));
    final ids = accounts.map((a) => a.id).toSet();
    final autopay = upcomingMandates(mandates, now, cycleEnd)
        .where((m) => ids.contains(m.physicalAccountId))
        .fold<int>(0, (s, m) => s + reserveUntil(m, cycleEnd));
    final bank = accounts
        .where((a) => !a.isLiability)
        .fold<int>(0, (s, a) => s + a.balanceMinorUnits);
    return CommitmentTotals(
      cards: cards,
      loans: loans,
      autopay: autopay,
      available: bank < 0 ? 0 : bank,
    );
  }

  final int cards;
  final int loans;
  final int autopay;

  /// What your bank and cash accounts hold.
  final int available;

  int get total => cards + loans + autopay;
}

/// Everything you have to pay, in one place: credit card bills (with their
/// own billing cycle and whether you can pay them), loans, and autopays due
/// before payday.
class BillsAndCommitments extends ConsumerWidget {
  const BillsAndCommitments({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref
        .watch(exchangeRatesProvider)
        .inHome(ref.watch(activePhysicalAccountsProvider).value ?? const []);
    final mandates = ref.watch(activeMandatesProvider).value ?? const [];
    final cycle = ref.watch(currentPaycycleProvider);
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final now = DateTime.now();

    final liabilities = accounts.where((a) => a.isLiability).toList();
    final cards = liabilities
        .where((a) => a.creditLimitMinorUnits > 0)
        .toList();
    final loans = liabilities
        .where((a) => a.creditLimitMinorUnits <= 0)
        .toList();
    int owedOn(PhysicalAccount a) =>
        a.balanceMinorUnits < 0 ? -a.balanceMinorUnits : 0;
    final bills = CardBills.of(accounts);

    final due = upcomingMandates(mandates, now, cycle.cycleEndDate);
    final accountIds = accounts.map((a) => a.id).toSet();
    final autopays = due.where((m) => accountIds.contains(m.physicalAccountId));

    if (cards.isEmpty && loans.isEmpty && autopays.isEmpty) {
      return Text(
        'Credit cards, loans and autopays you add show up here with their '
        'due dates.',
        style: RiveroTypography.bodySmall,
      );
    }

    Widget line(
      Widget leading,
      String title,
      String sub,
      String amount, {
      Color? subColor,
      VoidCallback? onTap,
      Key? key,
    }) {
      return Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
        child: RiveroCard(
          onTap: onTap,
          child: Row(
            children: [
              leading,
              const SizedBox(width: RiveroSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: RiveroTypography.bodyLarge),
                    Text(
                      sub,
                      style: RiveroTypography.bodySmall.copyWith(
                        color: subColor,
                      ),
                    ),
                  ],
                ),
              ),
              Text(amount, style: RiveroTypography.titleMedium),
            ],
          ),
        ),
      );
    }

    // A small title per group; credit cards also show what they owe in all.
    Widget group(String title, {String? total, Key? key}) => Padding(
      padding: const EdgeInsets.only(
        top: RiveroSpacing.sm,
        bottom: RiveroSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: RiveroTypography.titleMedium)),
          if (total != null)
            Text(
              total,
              key: key,
              style: RiveroTypography.titleMedium.copyWith(
                color: RiveroColors.warning,
              ),
            ),
        ],
      ),
    );
    final cardsOwed = cards.fold<int>(0, (s, c) => s + owedOn(c));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cards.isNotEmpty)
          group(
            'Credit cards',
            total: 'Owe ${money(cardsOwed)}',
            key: const ValueKey('cards-owed-total'),
          ),
        // Each card: what is left to settle, by when, and from which
        // account (enough there, or short by how much). Nothing else.
        for (final c in cards)
          () {
            final cc = CardCycle.of(
              statementDay: c.statementDay,
              paymentDueDay: c.paymentDueDay,
              now: now,
            );
            final owed = owedOn(c);
            final status = billStatus(bills, c, money);
            final when = owed == 0
                ? 'Nothing to settle'
                : cc == null
                ? 'Set the statement and due days on the card'
                : 'Settle by ${DateFormat('d MMM').format(cc.dueDate)} · '
                      '${cc.daysToDue == 0 ? 'today' : 'in ${cc.daysToDue} days'}';
            return line(
              BankBadge(
                name: c.institution,
                imagePath: c.imagePath,
                size: 40,
                circle: true,
              ),
              c.name,
              status == null ? when : '$when\n${status.text}',
              money(owed),
              subColor: status != null && !status.ok
                  ? RiveroColors.danger
                  : null,
              onTap: () => AccountDetailScreen.open(context, c.id),
              key: ValueKey('commit-card-${c.id}'),
            );
          }(),
        if (loans.isNotEmpty) group('Loans'),
        for (final l in loans)
          line(
            BankBadge(
              name: l.institution,
              imagePath: l.imagePath,
              size: 40,
              circle: true,
            ),
            l.name,
            '${l.accountType} · still owed',
            money(owedOn(l)),
            key: ValueKey('commit-loan-${l.id}'),
          ),
        if (autopays.isNotEmpty) group('Autopay before payday'),
        for (final m in autopays)
          line(
            MandateKindIcon(AutopayActions.kindOf(m), size: 40),
            m.payee,
            '${AutopayActions.kindOf(m).label} · '
            '${isOverdue(m, now) ? 'overdue since ' : ''}'
            '${DateFormat('d MMM').format(m.nextExecutionDate!)}',
            money(reserveUntil(m, cycle.cycleEndDate)),
            key: ValueKey('commit-autopay-${m.id}'),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => MandatesScreen.open(context),
            child: const Text('All autopays'),
          ),
        ),
      ],
    );
  }
}
