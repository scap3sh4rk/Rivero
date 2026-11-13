import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/features/accounts/screens/accounts_screen.dart';
import 'package:rivero/features/accounts/widgets/create_account_sheet.dart';
import 'package:rivero/features/budgets/screens/budgets_screen.dart';
import 'package:rivero/features/budgets/widgets/create_budget_sheet.dart';
import 'package:rivero/features/home/screens/home_screen.dart';
import 'package:rivero/features/home/widgets/simulate_sms_sheet.dart';
import 'package:rivero/features/settings/screens/settings_screen.dart';
import 'package:rivero/features/transactions/screens/transactions_screen.dart';
import 'package:rivero/features/transactions/widgets/create_transaction_sheet.dart';

/// Central application scaffold providing Cashew-inspired bottom navigation,
/// multi-tab coordination, and quick financial entry actions.
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  final List<Widget> _screens = const [
    HomeScreen(),
    AccountsScreen(),
    BudgetsScreen(),
    TransactionsScreen(),
    SettingsScreen(),
  ];

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: RiveroColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(RiveroRadii.xl),
          ),
          border: Border(
            top: BorderSide(color: RiveroColors.borderHighlight, width: 1.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: RiveroSpacing.xl,
          vertical: RiveroSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: RiveroColors.surfaceInteractive,
                  borderRadius: BorderRadius.circular(RiveroRadii.full),
                ),
              ),
            ),
            const SizedBox(height: RiveroSpacing.md),
            Text(
              'Quick Actions',
              style: RiveroTypography.titleMedium.copyWith(fontSize: 16),
            ),
            const SizedBox(height: RiveroSpacing.md),

            // 1. Add Transaction
            _buildActionTile(
              icon: Icons.receipt_long_rounded,
              color: RiveroColors.expenseAccent,
              title: 'Log Expense / Income',
              subtitle: 'Record a new spend against accounts & budget purposes',
              onTap: () {
                Navigator.pop(context);
                CreateTransactionSheet.show(this.context);
              },
            ),
            const SizedBox(height: RiveroSpacing.sm),

            // 2. Add Account
            _buildActionTile(
              icon: Icons.account_balance_rounded,
              color: RiveroColors.investmentAccent,
              title: 'Create Account',
              subtitle:
                  'Add bank, cash wallet, or credit card with 10%/30% alert',
              onTap: () {
                Navigator.pop(context);
                CreateAccountSheet.show(this.context);
              },
            ),
            const SizedBox(height: RiveroSpacing.sm),

            // 3. Add Budget Purpose
            _buildActionTile(
              icon: Icons.pie_chart_rounded,
              color: RiveroColors.salaryAccent,
              title: 'New Monthly Purpose Bucket',
              subtitle:
                  'Allocate monthly salary to a specific spending purpose',
              onTap: () {
                Navigator.pop(context);
                CreateBudgetSheet.show(this.context);
              },
            ),
            const SizedBox(height: RiveroSpacing.sm),

            // 4. Simulate SMS
            _buildActionTile(
              icon: Icons.bolt_rounded,
              color: RiveroColors.salaryAccent,
              title: 'Simulate Bank Notification',
              subtitle: 'Test on-device notification parsing and ledger ingest',
              onTap: () {
                Navigator.pop(context);
                SimulateSmsSheet.show(this.context);
              },
            ),
            const SizedBox(height: RiveroSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(RiveroRadii.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(RiveroSpacing.md),
        decoration: BoxDecoration(
          color: RiveroColors.surfaceElevated,
          borderRadius: BorderRadius.circular(RiveroRadii.md),
          border: Border.all(color: RiveroColors.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(RiveroSpacing.sm),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(RiveroRadii.sm),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: RiveroSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: RiveroTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: RiveroTypography.bodySmall.copyWith(
                      fontSize: 11,
                      color: RiveroColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: RiveroColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(selectedNavIndexProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      body: IndexedStack(index: currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: RiveroColors.borderSubtle)),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          backgroundColor: RiveroColors.surface,
          indicatorColor: RiveroColors.surfaceInteractive,
          elevation: 0,
          onDestinationSelected: (idx) {
            ref.read(selectedNavIndexProvider.notifier).state = idx;
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(
                Icons.dashboard_rounded,
                color: RiveroColors.salaryAccent,
              ),
              label: 'Overview',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_outlined),
              selectedIcon: Icon(
                Icons.account_balance_rounded,
                color: RiveroColors.investmentAccent,
              ),
              label: 'Accounts',
            ),
            NavigationDestination(
              icon: Icon(Icons.pie_chart_outline_rounded),
              selectedIcon: Icon(
                Icons.pie_chart_rounded,
                color: RiveroColors.salaryAccent,
              ),
              label: 'Budgets',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(
                Icons.receipt_long_rounded,
                color: RiveroColors.expenseAccent,
              ),
              label: 'Transactions',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(
                Icons.settings_rounded,
                color: RiveroColors.textPrimary,
              ),
              label: 'Settings',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: RiveroColors.surfaceElevated,
        foregroundColor: RiveroColors.salaryAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiveroRadii.md),
          side: const BorderSide(color: RiveroColors.borderHighlight),
        ),
        tooltip: 'Quick Actions',
        onPressed: () => _showQuickActions(context),
        child: const Icon(Icons.flash_on_rounded, size: 20),
      ),
    );
  }
}
