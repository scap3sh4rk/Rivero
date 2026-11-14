import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/plan/salary_plan_screen.dart';

/// Shown on Home until the user has added an account and a salary plan: the
/// two things the daily number needs. Each step ticks itself off.
class GetStartedCard extends ConsumerWidget {
  const GetStartedCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activePhysicalAccountsProvider).value;
    final salary = ref.watch(monthlySalaryProvider);
    if (accounts == null) return const SizedBox.shrink();
    final hasAccounts = accounts.isNotEmpty;
    final hasPlan = salary > 0;
    if (hasAccounts && hasPlan) return const SizedBox.shrink();

    Widget step(bool done, String title, String sub, VoidCallback onTap) =>
        InkWell(
          onTap: done ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: RiveroSpacing.sm),
            child: Row(
              children: [
                Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: done ? RiveroColors.success : RiveroColors.textMuted,
                ),
                const SizedBox(width: RiveroSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: RiveroTypography.bodyLarge),
                      Text(sub, style: RiveroTypography.bodySmall),
                    ],
                  ),
                ),
                if (!done) const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.xl),
      child: RiveroCard(
        key: const ValueKey('get-started'),
        isElevated: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Get started', style: RiveroTypography.titleMedium),
            const SizedBox(height: RiveroSpacing.xs),
            Text(
              'Two steps and your daily number appears.',
              style: RiveroTypography.bodySmall,
            ),
            const SizedBox(height: RiveroSpacing.sm),
            step(
              hasAccounts,
              'Add your accounts',
              'Banks, cards, cash: whatever you use',
              () => ref.read(selectedNavIndexProvider.notifier).state = 1,
            ),
            step(
              hasPlan,
              'Set your salary plan',
              'Your salary and where it goes each month',
              () => SalaryPlanScreen.open(context),
            ),
          ],
        ),
      ),
    );
  }
}
