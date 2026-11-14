import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// "How is this calculated?": every number behind the per-day figure.
class StsBreakdownSheet extends ConsumerWidget {
  const StsBreakdownSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RiveroColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const StsBreakdownSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(stsBreakdownProvider).value;
    final privacy = ref.watch(privacyModeProvider);
    if (b == null) return const SizedBox(height: 200);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final r = b.result;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          RiveroSpacing.xl,
          RiveroSpacing.xl,
          RiveroSpacing.xl,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How this is calculated',
                style: RiveroTypography.titleLarge,
              ),
              const SizedBox(height: RiveroSpacing.xs),
              Text(
                'Safe to spend is what you can use for everyday spending '
                'until your next payday, after setting aside what is already '
                'spoken for.',
                style: RiveroTypography.bodySmall,
              ),
              const SizedBox(height: RiveroSpacing.lg),

              _section('1 · Your spending budget'),
              _line('Planned for spending this cycle', money(b.planned)),
              if (b.carriedOver > 0)
                _line(
                  'Carried over from last cycle',
                  '+ ${money(b.carriedOver)}',
                ),
              _line('Spent so far', '− ${money(b.spent)}'),
              _total('Budget left', money(b.budgetLeft), warn: b.overBudget),
              if (b.setAside > 0)
                _note(
                  '${money(b.setAside)} is set aside for investments, savings '
                  'and other categories, so it is not counted here.',
                ),

              _section('2 · Money already spoken for'),
              _line(
                'Autopay due before payday'
                '${b.mandates.isEmpty ? '' : ' (${b.mandates.length})'}',
                b.mandatesTotal == 0 ? '₹0' : '− ${money(b.mandatesTotal)}',
              ),
              for (final m in b.mandates)
                _sub(
                  '${m.payee} · '
                  '${DateFormat('d MMM').format(m.nextExecutionDate!)}',
                  money(
                    m.isVariableAmount
                        ? (m.maxCapMinorUnits ?? m.amountMinorUnits)
                        : m.amountMinorUnits,
                  ),
                ),
              _line(
                'Credit card bills to pay',
                b.cardBills == 0 ? '₹0' : '− ${money(b.cardBills)}',
              ),
              if (b.owedIncluded && b.owedToYou > 0)
                _line('Owed to you (counted)', '+ ${money(b.owedToYou)}')
              else if (b.owedToYou > 0)
                _note(
                  '${money(b.owedToYou)} is owed to you. It is not counted '
                  'until it arrives (change in Settings).',
                ),

              _section('3 · Safe to spend'),
              _total(
                'Total until payday',
                money(r.effectiveSafeToSpend),
                warn: r.isDeficit,
              ),
              _line('Days to payday', '${b.daysToPayday}'),
              _total(
                'Per day',
                r.isDeficit ? '₹0' : money(r.dailySpendingPace),
                big: true,
                warn: r.isDeficit,
              ),
              if (r.isDeficit)
                _note(
                  b.overBudget
                      ? 'You have spent ${money(-b.budgetLeft)} more than '
                            'planned this cycle.'
                      : 'Autopay and card bills due are more than what is '
                            'left in your budget.',
                  warn: true,
                ),
              if (b.budgetExceedsAccount)
                _note(
                  'Your spending budget (${money(b.budgetLeft)}) is more than '
                  'the ${money(b.spendingAccountBalance!)} actually in the '
                  'account it draws from. Check the account balance.',
                  warn: true,
                ),
              _note(switch (r.reliability) {
                BalanceReliability.verified =>
                  'Figures are up to date (updated in the last 24 hours).',
                BalanceReliability.estimated =>
                  'Figures were last updated 1–3 days ago.',
                BalanceReliability.stale =>
                  'Figures were last updated over 3 days ago. Log recent '
                      'spends to refresh.',
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(
      top: RiveroSpacing.lg,
      bottom: RiveroSpacing.xs,
    ),
    child: Text(
      text.toUpperCase(),
      style: RiveroTypography.labelSmall.copyWith(letterSpacing: 1.2),
    ),
  );

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: RiveroTypography.bodyMedium)),
        const SizedBox(width: RiveroSpacing.md),
        Text(value, style: RiveroTypography.bodyLarge),
      ],
    ),
  );

  Widget _sub(String label, String value) => Padding(
    padding: const EdgeInsets.only(left: RiveroSpacing.lg, bottom: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: RiveroTypography.bodySmall)),
        Text(value, style: RiveroTypography.bodySmall),
      ],
    ),
  );

  Widget _total(
    String label,
    String value, {
    bool big = false,
    bool warn = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: RiveroTypography.titleMedium)),
        Text(
          value,
          key: ValueKey('sts-${label.toLowerCase().replaceAll(' ', '-')}'),
          style:
              (big
                      ? RiveroTypography.financialMedium
                      : RiveroTypography.titleMedium)
                  .copyWith(color: warn ? RiveroColors.danger : null),
        ),
      ],
    ),
  );

  Widget _note(String text, {bool warn = false}) => Padding(
    padding: const EdgeInsets.only(top: RiveroSpacing.xs),
    child: Text(
      text,
      style: RiveroTypography.bodySmall.copyWith(
        color: warn ? RiveroColors.warning : null,
      ),
    ),
  );
}
