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

  late final PageController _pager = PageController();

  static const _tabs = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Overview'),
    (
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
      'Accounts',
    ),
    (Icons.donut_small_outlined, Icons.donut_small_rounded, 'Budgets'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Transactions'),
    (Icons.tune_rounded, Icons.tune_rounded, 'Settings'),
  ];

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    ref.read(selectedNavIndexProvider.notifier).state = i;
    _pager.animateToPage(
      i,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(selectedNavIndexProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      body: PageView(
        controller: _pager,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (i) =>
            ref.read(selectedNavIndexProvider.notifier).state = i,
        children: _screens,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RiveroSpacing.lg,
            0,
            RiveroSpacing.lg,
            RiveroSpacing.md,
          ),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: RiveroColors.surfaceElevated,
              borderRadius: RiveroRadii.borderFull,
              border: Border.all(color: RiveroColors.borderSubtle),
            ),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: _NavItem(
                      key: ValueKey('nav-${_tabs[i].$3}'),
                      icon: _tabs[i].$1,
                      selectedIcon: _tabs[i].$2,
                      label: _tabs[i].$3,
                      selected: i == currentIndex,
                      onTap: () => _goTo(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        elevation: 0,
        backgroundColor: RiveroColors.textPrimary,
        foregroundColor: RiveroColors.background,
        shape: const CircleBorder(),
        tooltip: 'Quick Actions',
        onPressed: () => _showQuickActions(context),
        child: const Icon(Icons.add_rounded, size: 24),
      ),
    );
  }
}

/// Nav item: icon with a label that springs in only for the active tab.
class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.0 : 0.88,
          duration: const Duration(milliseconds: 350),
          curve: Curves.elasticOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 22,
                color: selected
                    ? RiveroColors.textPrimary
                    : RiveroColors.textMuted,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          label,
                          style: RiveroTypography.labelSmall.copyWith(
                            fontSize: 9,
                            color: RiveroColors.textPrimary,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
