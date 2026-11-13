import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/features/home/widgets/safe_to_spend_hero_card.dart';
import 'package:rivero/features/home/widgets/salary_prompt.dart';
import 'package:rivero/features/home/widgets/simulate_sms_sheet.dart';
import 'package:rivero/features/home/widgets/transaction_swiper_section.dart';

/// Home: one hero number and, only when needed, the triage inbox.
/// Accounts, budgets and history live on their own pages (no repeated data).
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
            icon: Icon(Icons.bolt_rounded, color: RiveroColors.textSecondary),
            onPressed: () => SimulateSmsSheet.show(context),
          ),
          IconButton(
            tooltip: 'Toggle Privacy Mode',
            icon: Icon(
              isPrivacy
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: RiveroColors.textSecondary,
            ),
            onPressed: () =>
                ref.read(privacyModeProvider.notifier).state = !isPrivacy,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            RiveroSpacing.lg,
            RiveroSpacing.xxxl,
            RiveroSpacing.lg,
            RiveroSpacing.huge * 2,
          ),
          children: const [
            SafeToSpendHeroCard(),
            SizedBox(height: RiveroSpacing.huge),
            SalaryPrompt(),
            TransactionSwiperSection(),
          ],
        ),
      ),
    );
  }
}
