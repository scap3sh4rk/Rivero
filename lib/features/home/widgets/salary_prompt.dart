import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/plan/salary_plan_screen.dart';

/// Appears only when a salary credit has arrived and is not split yet.
class SalaryPrompt extends ConsumerWidget {
  const SalaryPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salary = ref.watch(pendingSalaryProvider).value;
    if (salary == null) return const SizedBox.shrink();
    final privacy = ref.watch(privacyModeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.xl),
      child: RiveroCard(
        isElevated: true,
        onTap: () => SalaryPlanScreen.open(context, salaryTransaction: salary),
        child: Row(
          children: [
            const Icon(
              Icons.payments_outlined,
              color: RiveroColors.salaryAccent,
            ),
            const SizedBox(width: RiveroSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    privacy
                        ? 'Salary received'
                        : '${CurrencyFormatter.format(salary.amountMinorUnits)} received',
                    style: RiveroTypography.titleMedium,
                  ),
                  Text(
                    'Tap to split it into your plan',
                    style: RiveroTypography.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
