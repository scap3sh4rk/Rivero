import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/features/home/widgets/accounts_and_buckets_list.dart';
import 'package:rivero/features/home/widgets/recent_activity_list.dart';
import 'package:rivero/features/home/widgets/safe_to_spend_hero_card.dart';
import 'package:rivero/features/home/widgets/simulate_sms_sheet.dart';
import 'package:rivero/features/home/widgets/transaction_swiper_section.dart';

/// The central Interactive Home Screen of Rivero.
/// Coordinates the Safe-to-Spend Hero, Transaction Swiper, Accounts/Buckets, and Activity feed.
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
              ..invalidate(recentTransactionsProvider);
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
                SizedBox(height: RiveroSpacing.xl),

                // 2. Interactive Card Swiper for Transaction Review
                TransactionSwiperSection(),
                SizedBox(height: RiveroSpacing.xl),

                // 3. Custodial Accounts & Virtual Waterfall Buckets
                AccountsAndBucketsList(),
                SizedBox(height: RiveroSpacing.xl),

                // 4. Encrypted Transaction Activity Stream
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
