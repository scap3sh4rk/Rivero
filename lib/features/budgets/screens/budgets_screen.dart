import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/plan/plan_transfer_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/plan/salary_plan_screen.dart';

/// Plan: where this month's salary goes. One card for the salary, one short
/// row per category. Editing happens on the Salary plan page.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  /// A plan-only category (nothing moved yet): record that it was paid, out
  /// of the salary account.
  Future<void> _markPaid(
    BuildContext context,
    WidgetRef ref,
    AllocationBucket b,
  ) async {
    if (b.role == AccountRole.expense ||
        b.allocatedMinorUnits <= 0 ||
        b.spentMinorUnits > 0) {
      return;
    }
    // Read from the database, not a provider that may still be loading.
    final db = ref.read(databaseProvider);
    final accounts = (await db.accountsDao.getAllActivePhysicalAccounts())
        .where((a) => !a.isLiability)
        .toList();
    final salary = PlanTransferService.salaryAccountOf(
      accounts,
      await db.settingsDao.get(SettingKeys.salaryAccount),
    );
    if (salary == null || !context.mounted) return;
    // A category that pays into a tracked account is moved by the plan.
    if (b.linkedPhysicalAccountId != null &&
        b.linkedPhysicalAccountId != salary.id) {
      return;
    }
    final amount = CurrencyFormatter.format(b.allocatedMinorUnits);
    // A bank account never goes below zero because of a plan: if the salary
    // account cannot cover it, the money must have left before Rivero knew.
    final canPayNow = salary.balanceMinorUnits >= b.allocatedMinorUnits;
    final choice = await showDialog<_Paid>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark ${b.name} as paid'),
        content: Text(
          canPayNow
              ? 'Already paid: pick the day you paid. It is added to '
                    'Activity; your balance is not changed.\n'
                    'Paying now: $amount is taken out of ${salary.name}.'
              : '${salary.name} holds '
                    '${CurrencyFormatter.format(salary.balanceMinorUnits)}, '
                    'less than $amount, so this was paid before. Pick the day '
                    'you paid; the balance is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not yet'),
          ),
          if (canPayNow)
            TextButton(
              key: const ValueKey('pay-now'),
              onPressed: () => Navigator.pop(ctx, _Paid.now),
              child: const Text('Paying now'),
            ),
          FilledButton(
            key: const ValueKey('already-paid'),
            onPressed: () => Navigator.pop(ctx, _Paid.before),
            child: const Text('Already paid'),
          ),
        ],
      ),
    );
    switch (choice) {
      case null:
        return;
      case _Paid.before:
        // When was it paid? That day's entry appears in Activity.
        if (!context.mounted) return;
        final now = DateTime.now();
        final on = await showDatePicker(
          context: context,
          helpText: 'When did you pay ${b.name}?',
          initialDate: now,
          firstDate: DateTime(now.year - 1),
          lastDate: now,
        );
        if (on == null) return;
        await ref
            .read(salaryPlanServiceProvider)
            .recordPaidOn(
              bucketId: b.id,
              accountId: salary.id,
              on: DateTime(on.year, on.month, on.day, 12),
            );
      case _Paid.now:
        await ref
            .read(ledgerServiceProvider)
            .recordManual(
              accountId: salary.id,
              amountMinorUnits: -b.allocatedMinorUnits,
              type: TransactionType.planTransfer,
              merchant: 'Plan: ${b.name}',
              category: b.name,
              bucketId: b.id,
            );
    }
  }

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const BudgetsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = ref.watch(allAllocationBucketsProvider).value ?? const [];
    final salary = ref.watch(monthlySalaryProvider);
    final privacy = ref.watch(privacyModeProvider);
    // Spending "left" is the same number Home uses (the account's real
    // balance when one is linked), never a separate budget sum.
    final sts = ref.watch(stsBreakdownProvider).value;

    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);

    final ordered = [...buckets]
      ..sort((a, b) {
        // Spending first, then the set-aside categories in plan order.
        int rank(AllocationBucket x) => x.role == AccountRole.expense ? 0 : 1;
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.priorityOrder.compareTo(b.priorityOrder);
      });
    final setAside = buckets
        .where((b) => b.role != AccountRole.expense)
        .fold<int>(0, (s, b) => s + b.allocatedMinorUnits);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Plan',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge,
        ),
        children: [
          RiveroCard(
            isElevated: true,
            onTap: () => SalaryPlanScreen.open(context),
            padding: const EdgeInsets.all(RiveroSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'MONTHLY SALARY',
                        style: RiveroTypography.labelSmall.copyWith(
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    Text(
                      salary == 0 ? 'Set up' : 'Edit plan',
                      style: RiveroTypography.labelLarge,
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: RiveroColors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.sm),
                Text(
                  salary == 0 ? 'Not set' : money(salary),
                  style: RiveroTypography.financialLarge,
                ),
                if (salary > 0) ...[
                  const SizedBox(height: RiveroSpacing.xs),
                  Text(
                    '${money(setAside)} set aside · '
                    '${money((salary - setAside).clamp(0, salary))} for spending',
                    style: RiveroTypography.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: RiveroSpacing.xl),
          Text('Categories', style: RiveroTypography.titleMedium),
          const SizedBox(height: RiveroSpacing.sm),
          if (ordered.isEmpty)
            Text(
              'Set up your salary plan to create categories.',
              style: RiveroTypography.bodySmall,
            ),
          for (final b in ordered)
            _CategoryTile(
                  b,
                  money: money,
                  spendingLeft: sts?.usable,
                  spendingTotal: sts?.planTotal,
                  fromAccount: sts?.fromAccount ?? false,
                  onTap: () => _markPaid(context, ref, b),
                )
                .animate()
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.05, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }
}

enum _Paid { before, now }

class _CategoryTile extends StatelessWidget {
  const _CategoryTile(
    this.b, {
    required this.money,
    this.onTap,
    this.spendingLeft,
    this.spendingTotal,
    this.fromAccount = false,
  });

  final int? spendingLeft;
  final int? spendingTotal;
  final bool fromAccount;

  final VoidCallback? onTap;

  final AllocationBucket b;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) {
    final spending = b.role == AccountRole.expense;
    final total = spending
        ? (spendingTotal ?? b.allocatedMinorUnits + b.carryOverMinorUnits)
        : b.allocatedMinorUnits + b.carryOverMinorUnits;
    final left =
        spendingLeft ??
        b.allocatedMinorUnits + b.carryOverMinorUnits - b.spentMinorUnits;
    // Spending shows what is left; set-aside categories show what is reserved
    // (and how much of it has been paid, for things like rent).
    final detail = spending
        ? (left > total
                  ? '${money(left)} left · ${money(total)} planned'
                  : '${money(left)} left of ${money(total)}') +
              (fromAccount ? ' · from your account balance' : '')
        : b.spentMinorUnits > 0
        ? '${money(b.spentMinorUnits)} paid of ${money(total)}'
        : '${money(total)} set aside';
    final used = total <= 0
        ? 0.0
        : spending
        ? (1 - left / total).clamp(0.0, 1.0)
        : (b.spentMinorUnits / total).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
      child: RiveroCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.name, style: RiveroTypography.bodyLarge),
            const SizedBox(height: RiveroSpacing.xs),
            Text(
              detail,
              style: RiveroTypography.bodySmall.copyWith(
                color: spending && left < 0 ? RiveroColors.danger : null,
              ),
            ),
            if (!spending &&
                b.spentMinorUnits == 0 &&
                b.allocatedMinorUnits > 0 &&
                b.linkedPhysicalAccountId == null) ...[
              const SizedBox(height: RiveroSpacing.xs),
              Text('Tap when paid', style: RiveroTypography.bodySmall),
            ],
            if (spending || b.spentMinorUnits > 0) ...[
              const SizedBox(height: RiveroSpacing.sm),
              ClipRRect(
                borderRadius: RiveroRadii.borderFull,
                child: LinearProgressIndicator(
                  value: used,
                  minHeight: 4,
                  backgroundColor: RiveroColors.surfaceInteractive,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    RiveroColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
