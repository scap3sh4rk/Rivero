import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/brand_wordmark.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/features/home/widgets/backup_reminder_card.dart';
import 'package:rivero/features/home/widgets/capture_hint_card.dart';
import 'package:rivero/features/home/widgets/get_started_card.dart';
import 'package:rivero/features/home/widgets/goals_home_card.dart';
import 'package:rivero/features/home/widgets/home_shortcuts.dart';
import 'package:rivero/features/home/widgets/review_inbox.dart';
import 'package:rivero/features/home/widgets/safe_to_spend_hero_card.dart';
import 'package:rivero/features/home/widgets/salary_prompt.dart';
import 'package:rivero/features/home/widgets/simulate_sms_sheet.dart';

/// Home: one hero number and, only when needed, the triage inbox.
/// Accounts, budgets and history live on their own pages (no repeated data).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paycycle = ref.watch(currentPaycycleProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Rivero',
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Decoded at its display size with the best filter: crisp edges.
            Image.asset(
              'assets/icon/logo.png',
              width: 38,
              height: 38,
              cacheWidth: 152,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(width: RiveroSpacing.sm),
            const BrandWordmark(fontSize: 34),
          ],
        ),
        subtitle: 'Paycycle · ${paycycle.daysRemaining} days left',
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'Simulate Notification',
              icon: Icon(Icons.bolt_rounded, color: RiveroColors.textSecondary),
              onPressed: () => SimulateSmsSheet.show(context),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            RiveroSpacing.lg,
            RiveroSpacing.xxxl,
            RiveroSpacing.lg,
            RiveroSpacing.huge + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const SafeToSpendHeroCard()
                .animate()
                .fadeIn(duration: 350.ms)
                .slideY(begin: 0.06, curve: Curves.easeOutCubic),
            const SizedBox(height: RiveroSpacing.huge),
            const GetStartedCard(),
            const CaptureHintCard(),
            const BackupReminderCard(),
            const SalaryPrompt(),
            const ReviewInbox(),
            const SizedBox(height: RiveroSpacing.lg),
            const HomeShortcuts(),
            const GoalsHomeCard(),
          ],
        ),
      ),
    );
  }
}
