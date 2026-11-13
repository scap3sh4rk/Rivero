import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/financial_amount_text.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_button.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/role_badge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: RiveroApp()));
}

/// Root widget of the Rivero application.
class RiveroApp extends StatelessWidget {
  const RiveroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rivero',
      debugShowCheckedModeBanner: false,
      theme: RiveroTheme.darkTheme,
      home: const RiveroFoundationScreen(),
    );
  }
}

/// Foundation screen showcasing Rivero design system and Riverpod integration.
class RiveroFoundationScreen extends ConsumerWidget {
  const RiveroFoundationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safeToSpend = ref.watch(safeToSpendProvider);
    final isPrivacy = ref.watch(privacyModeProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Rivero',
        subtitle: 'Waterfall Allocation & Liquidity',
        actions: [
          IconButton(
            icon: Icon(
              isPrivacy ? Icons.visibility_off : Icons.visibility,
              color: RiveroColors.textSecondary,
              size: 20,
            ),
            tooltip: 'Toggle Privacy Mode',
            onPressed: () {
              ref.read(privacyModeProvider.notifier).state = !isPrivacy;
            },
          ),
          const SizedBox(width: RiveroSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RiveroSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Safe-to-Spend Hero Card ---
              RiveroCard(
                    isElevated: true,
                    padding: const EdgeInsets.all(RiveroSpacing.xl),
                    borderColor: RiveroColors.borderHighlight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'SAFE TO SPEND',
                              style: RiveroTypography.labelSmall.copyWith(
                                letterSpacing: 1.5,
                                color: RiveroColors.textMuted,
                              ),
                            ),
                            const RoleBadge(
                              role: AccountRole.expense,
                              isCompact: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: RiveroSpacing.sm),
                        if (isPrivacy)
                          Text(
                            '••••••••',
                            style: RiveroTypography.financialHero.copyWith(
                              color: RiveroColors.textPrimary,
                            ),
                          )
                        else
                          FinancialAmountText(
                            minorUnits: safeToSpend,
                            size: FinancialAmountSize.hero,
                            isAnimated: true,
                          ),
                        const SizedBox(height: RiveroSpacing.xs),
                        Row(
                          children: [
                            const Icon(
                              Icons.speed,
                              size: 14,
                              color: RiveroColors.savingsAccent,
                            ),
                            const SizedBox(width: RiveroSpacing.xs),
                            Text(
                              'Pace: ₹2,412 / day · 20 days left in cycle',
                              style: RiveroTypography.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.1, end: 0, duration: 400.ms),

              const SizedBox(height: RiveroSpacing.xl),

              // --- Allocation Buckets Header ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Allocation Buckets',
                    style: RiveroTypography.titleMedium,
                  ),
                  Text(
                    'Root: ₹1,50,000',
                    style: RiveroTypography.monoSmall.copyWith(
                      color: RiveroColors.salaryAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RiveroSpacing.md),

              // --- Bucket Cards ---
              _BucketPreviewCard(
                role: AccountRole.salaryRoot,
                name: 'Primary HDFC Salary',
                accountMask: '••4012',
                balanceMinorUnits: 15000000,
                isPrivacy: isPrivacy,
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05, end: 0),

              const SizedBox(height: RiveroSpacing.sm),

              _BucketPreviewCard(
                role: AccountRole.expense,
                name: 'Monthly Expenses',
                accountMask: '••8841',
                balanceMinorUnits: 4825000,
                isPrivacy: isPrivacy,
              ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.05, end: 0),

              const SizedBox(height: RiveroSpacing.sm),

              _BucketPreviewCard(
                role: AccountRole.investment,
                name: 'Mutual Funds & Equity SIP',
                accountMask: 'Zerodha',
                balanceMinorUnits: 6000000,
                isPrivacy: isPrivacy,
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05, end: 0),

              const SizedBox(height: RiveroSpacing.sm),

              _BucketPreviewCard(
                role: AccountRole.savings,
                name: 'Emergency Fund',
                accountMask: '••1932',
                balanceMinorUnits: 3000000,
                isPrivacy: isPrivacy,
              ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.05, end: 0),

              const SizedBox(height: RiveroSpacing.sm),

              _BucketPreviewCard(
                role: AccountRole.liabilityCc,
                name: 'ICICI Sapphiro',
                accountMask: '••7102',
                balanceMinorUnits: -1425000,
                isPrivacy: isPrivacy,
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.05, end: 0),

              const SizedBox(height: RiveroSpacing.xl),

              // --- Quick Actions ---
              Row(
                children: [
                  Expanded(
                    child: RiveroButton(
                      label: 'Adjust Spend',
                      icon: Icons.tune,
                      variant: RiveroButtonVariant.secondary,
                      onPressed: () {
                        ref.read(safeToSpendProvider.notifier).state += 100000;
                      },
                    ),
                  ),
                  const SizedBox(width: RiveroSpacing.md),
                  Expanded(
                    child: RiveroButton(
                      label: 'Allocate',
                      icon: Icons.waterfall_chart,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: RiveroColors.surfaceElevated,
                            content: Text(
                              'Waterfall allocation engine initialized',
                              style: RiveroTypography.bodyMedium,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 350.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _BucketPreviewCard extends StatelessWidget {
  const _BucketPreviewCard({
    required this.role,
    required this.name,
    required this.accountMask,
    required this.balanceMinorUnits,
    required this.isPrivacy,
  });

  final AccountRole role;
  final String name;
  final String accountMask;
  final int balanceMinorUnits;
  final bool isPrivacy;

  @override
  Widget build(BuildContext context) {
    return RiveroCard(
      padding: const EdgeInsets.symmetric(
        horizontal: RiveroSpacing.lg,
        vertical: RiveroSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: role.accentColor.withValues(alpha: 0.15),
              borderRadius: RiveroRadii.borderSm,
            ),
            child: Icon(_getRoleIcon(role), size: 18, color: role.accentColor),
          ),
          const SizedBox(width: RiveroSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: RiveroTypography.titleMedium.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(accountMask, style: RiveroTypography.monoSmall),
                    const SizedBox(width: RiveroSpacing.sm),
                    RoleBadge(role: role, isCompact: true),
                  ],
                ),
              ],
            ),
          ),
          if (isPrivacy)
            Text('••••••', style: RiveroTypography.monoMedium)
          else
            FinancialAmountText(
              minorUnits: balanceMinorUnits,
              size: FinancialAmountSize.small,
              customColor: balanceMinorUnits < 0
                  ? RiveroColors.danger
                  : RiveroColors.textPrimary,
            ),
        ],
      ),
    );
  }

  IconData _getRoleIcon(AccountRole role) {
    switch (role) {
      case AccountRole.salaryRoot:
        return Icons.account_balance;
      case AccountRole.expense:
        return Icons.shopping_bag_outlined;
      case AccountRole.investment:
        return Icons.trending_up;
      case AccountRole.savings:
        return Icons.savings_outlined;
      case AccountRole.custom:
        return Icons.folder_outlined;
      case AccountRole.liabilityCc:
        return Icons.credit_card;
      case AccountRole.virtualWallet:
        return Icons.account_balance_wallet_outlined;
    }
  }
}
