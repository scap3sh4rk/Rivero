import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/features/accounts/widgets/create_account_sheet.dart';
import 'package:rivero/features/budgets/widgets/create_budget_sheet.dart';
import 'package:rivero/features/home/widgets/accounts_and_buckets_list.dart';
import 'package:rivero/features/home/widgets/recent_activity_list.dart';
import 'package:rivero/features/home/widgets/safe_to_spend_hero_card.dart';
import 'package:rivero/features/home/widgets/simulate_sms_sheet.dart';
import 'package:rivero/features/home/widgets/transaction_swiper_section.dart';
import 'package:rivero/features/transactions/widgets/create_transaction_sheet.dart';

/// The central Interactive Home Screen of Rivero.
/// Coordinates the Safe-to-Spend Hero, Quick Action Bar, Transaction Swiper, Accounts/Buckets, and Activity feed.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPrivacy = ref.watch(privacyModeProvider);
    final paycycle = ref.watch(currentPaycycleProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Rivero',
        subtitle: 'Paycycle · ${paycycle.daysRemaining} days left',
        actions: [
          IconButton(
            tooltip: 'Simulate Notification',
            icon: const Icon(
              Icons.bolt_rounded,
              color: RiveroColors.salaryAccent,
            ),
            onPressed: () => SimulateSmsSheet.show(context),
          ),
          IconButton(
            tooltip: 'Toggle Privacy Mode',
            icon: Icon(
              isPrivacy ? Icons.visibility_off : Icons.visibility,
              color: RiveroColors.textSecondary,
            ),
            onPressed: () {
              ref.read(privacyModeProvider.notifier).state = !isPrivacy;
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: RiveroColors.expenseAccent,
          backgroundColor: RiveroColors.surfaceElevated,
          onRefresh: () async {
            // Trigger refresh on all major stream providers
            ref
              ..invalidate(allAllocationBucketsProvider)
              ..invalidate(activePhysicalAccountsProvider)
              ..invalidate(pendingReviewTransactionsProvider)
              ..invalidate(recentTransactionsProvider)
              ..invalidate(allTransactionsStreamProvider);
          },
          child: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: RiveroSpacing.lg,
              vertical: RiveroSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Primary Safe-to-Spend Hero Card
                SafeToSpendHeroCard(),
                SizedBox(height: RiveroSpacing.md),

                // 2. Quick Action Buttons
                _QuickActionBar(),
                SizedBox(height: RiveroSpacing.xl),

                // 3. Interactive Card Swiper for Transaction Review
                TransactionSwiperSection(),
                SizedBox(height: RiveroSpacing.xl),

                // 4. Custodial Accounts & Virtual Waterfall Buckets
                AccountsAndBucketsList(),
                SizedBox(height: RiveroSpacing.xl),

                // 5. Encrypted Transaction Activity Stream
                RecentActivityList(),
                SizedBox(height: RiveroSpacing.xxxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionBar extends StatelessWidget {
  const _QuickActionBar();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ActionButton(
            icon: Icons.receipt_long_rounded,
            color: RiveroColors.expenseAccent,
            label: '+ Expense',
            onTap: () => CreateTransactionSheet.show(context),
          ),
          const SizedBox(width: RiveroSpacing.sm),
          _ActionButton(
            icon: Icons.account_balance_rounded,
            color: RiveroColors.investmentAccent,
            label: '+ Account',
            onTap: () => CreateAccountSheet.show(context),
          ),
          const SizedBox(width: RiveroSpacing.sm),
          _ActionButton(
            icon: Icons.pie_chart_rounded,
            color: RiveroColors.salaryAccent,
            label: '+ Budget',
            onTap: () => CreateBudgetSheet.show(context),
          ),
          const SizedBox(width: RiveroSpacing.sm),
          _ActionButton(
            icon: Icons.bolt_rounded,
            color: RiveroColors.savingsAccent,
            label: '⚡ Simulate',
            onTap: () => SimulateSmsSheet.show(context),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(RiveroRadii.full),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RiveroSpacing.md,
          vertical: RiveroSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: RiveroColors.surfaceElevated,
          borderRadius: BorderRadius.circular(RiveroRadii.full),
          border: Border.all(color: RiveroColors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: RiveroSpacing.xs),
            Text(
              label,
              style: RiveroTypography.labelSmall.copyWith(
                fontWeight: FontWeight.w600,
                color: RiveroColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
