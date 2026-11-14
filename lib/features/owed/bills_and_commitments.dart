import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/card_cycle.dart';
import 'package:rivero/core/domain/credit_utilization.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
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
    final accounts =
        ref.watch(activePhysicalAccountsProvider).value ?? const [];
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
    final bankTotal = accounts
        .where((a) => !a.isLiability)
        .fold<int>(0, (s, a) => s + a.balanceMinorUnits);
    final available = bankTotal < 0 ? 0 : bankTotal;

    final due = upcomingMandates(mandates, now, cycle.cycleEndDate);
    final accountIds = accounts.map((a) => a.id).toSet();
    final autopays = due.where((m) => accountIds.contains(m.physicalAccountId));
    final autopayTotal = autopays.fold<int>(
      0,
      (s, m) => s + reserveUntil(m, cycle.cycleEndDate),
    );
    final cardsTotal = cards.fold<int>(0, (s, a) => s + owedOn(a));
    final loansTotal = loans.fold<int>(0, (s, a) => s + owedOn(a));

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
      Key? key,
    }) {
      return Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
        child: RiveroCard(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RiveroCard(
          key: const ValueKey('commitments-total'),
          isElevated: true,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'To pay before payday',
                      style: RiveroTypography.bodySmall,
                    ),
                    Text(
                      money(cardsTotal + loansTotal + autopayTotal),
                      style: RiveroTypography.financialMedium,
                    ),
                  ],
                ),
              ),
              Text(
                'You hold ${money(available)}',
                style: RiveroTypography.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: RiveroSpacing.sm),
        for (final c in cards)
          () {
            final u = CreditUtilization.fromBalance(
              creditLimitMinorUnits: c.creditLimitMinorUnits,
              balanceMinorUnits: c.balanceMinorUnits,
            );
            final cc = CardCycle.of(
              statementDay: c.statementDay,
              paymentDueDay: c.paymentDueDay,
              now: now,
            );
            final owed = owedOn(c);
            final afford = CardAffordability(owed: owed, available: available);
            final sub =
                StringBuffer(
                  cc == null
                      ? 'Add statement and due days'
                      : 'Pay by ${DateFormat('d MMM').format(cc.dueDate)} · '
                            '${cc.daysToDue == 0 ? 'today' : '${cc.daysToDue} days'}',
                )..write(
                  ' · limit ${money(u.creditLimitMinorUnits)}, '
                  'available ${money(u.availableMinorUnits)}',
                );
            return line(
              BankBadge(
                name: c.institution,
                imagePath: c.imagePath,
                size: 40,
                circle: true,
              ),
              c.name,
              owed == 0
                  ? sub.toString()
                  : '$sub\n${afford.canPay ? 'You can pay this' : 'Short by ${money(afford.shortBy)}'}',
              money(owed),
              subColor: owed > 0 && !afford.canPay ? RiveroColors.danger : null,
              key: ValueKey('commit-card-${c.id}'),
            );
          }(),
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
        for (final m in autopays)
          line(
            const Icon(
              Icons.autorenew_rounded,
              color: RiveroColors.mandateWarning,
              size: 28,
            ),
            m.payee,
            'Autopay · ${isOverdue(m, now) ? 'overdue since ' : ''}'
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
