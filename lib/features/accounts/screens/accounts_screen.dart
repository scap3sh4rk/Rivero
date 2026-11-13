import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/accounts/widgets/create_account_sheet.dart';
import 'package:rivero/features/accounts/widgets/credit_utilization_card.dart';

/// Screen presenting the user's physical bank accounts, cash wallets,
/// and credit accounts with real-time credit score utilization tracking.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(activePhysicalAccountsProvider);
    final isPrivacy = ref.watch(privacyModeProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Accounts',
        subtitle: 'Balances and credit lines',
        actions: [
          IconButton(
            tooltip: 'Add Account',
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: RiveroColors.investmentAccent,
            ),
            onPressed: () => CreateAccountSheet.show(context),
          ),
        ],
      ),
      body: accountsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              RiveroColors.investmentAccent,
            ),
          ),
        ),
        error: (err, _) => Center(
          child: Text(
            'Failed to load accounts: $err',
            style: RiveroTypography.bodyMedium.copyWith(
              color: RiveroColors.danger,
            ),
          ),
        ),
        data: (accounts) {
          final creditAccounts = accounts.where((a) => a.isLiability).toList();
          final bankAccounts = accounts.where((a) => !a.isLiability).toList();

          // Compute aggregate totals
          var totalBankMinorUnits = 0;
          for (final a in bankAccounts) {
            totalBankMinorUnits += a.balanceMinorUnits;
          }

          var totalDebtMinorUnits = 0;
          for (final a in creditAccounts) {
            if (a.balanceMinorUnits < 0) {
              totalDebtMinorUnits += a.balanceMinorUnits.abs();
            }
          }

          final netWorthMinorUnits = totalBankMinorUnits - totalDebtMinorUnits;

          return RefreshIndicator(
            color: RiveroColors.investmentAccent,
            backgroundColor: RiveroColors.surfaceElevated,
            onRefresh: () async {
              ref.invalidate(activePhysicalAccountsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: RiveroSpacing.lg,
                vertical: RiveroSpacing.md,
              ),
              children: [
                // 1. Portfolio Net Worth Summary Card
                RiveroCard(
                  isElevated: true,
                  padding: const EdgeInsets.all(RiveroSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL NET WORTH',
                        style: RiveroTypography.labelSmall.copyWith(
                          letterSpacing: 1.2,
                          color: RiveroColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: RiveroSpacing.xs),
                      if (isPrivacy)
                        Text('••••••••', style: RiveroTypography.financialLarge)
                      else
                        Text(
                          CurrencyFormatter.format(netWorthMinorUnits),
                          style: RiveroTypography.financialLarge.copyWith(
                            color: netWorthMinorUnits >= 0
                                ? RiveroColors.textPrimary
                                : RiveroColors.danger,
                          ),
                        ),
                      const SizedBox(height: RiveroSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _SummaryPill(
                            label: 'Bank & Cash',
                            amountMinorUnits: totalBankMinorUnits,
                            color: RiveroColors.investmentAccent,
                            isPrivacy: isPrivacy,
                          ),
                          _SummaryPill(
                            label: 'Credit Outstanding',
                            amountMinorUnits: totalDebtMinorUnits,
                            color: RiveroColors.liabilityAccent,
                            isPrivacy: isPrivacy,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: RiveroSpacing.xl),

                // 2. Credit Lines & Utilization Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CREDIT LINE USAGE',
                      style: RiveroTypography.labelSmall.copyWith(
                        letterSpacing: 1.5,
                        color: RiveroColors.textMuted,
                      ),
                    ),
                    Text(
                      '10% Safe · 30% Score Alert',
                      style: RiveroTypography.labelSmall.copyWith(
                        color: RiveroColors.salaryAccent,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.sm),

                if (creditAccounts.isEmpty)
                  RiveroCard(
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.credit_card_off_rounded,
                            color: RiveroColors.textMuted,
                            size: 28,
                          ),
                          const SizedBox(height: RiveroSpacing.xs),
                          Text(
                            'No Credit Accounts',
                            style: RiveroTypography.titleMedium,
                          ),
                          Text(
                            'Add a credit card or credit line to track your 10%/30% utilization.',
                            style: RiveroTypography.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...creditAccounts.map(
                    (account) => Padding(
                      padding: const EdgeInsets.only(bottom: RiveroSpacing.md),
                      child: GestureDetector(
                        onTap: () =>
                            CreateAccountSheet.show(context, existing: account),
                        child: CreditUtilizationCard(account: account),
                      ),
                    ),
                  ),

                const SizedBox(height: RiveroSpacing.lg),

                // 3. Bank & Cash Accounts Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'BANK & CASH',
                      style: RiveroTypography.labelSmall.copyWith(
                        letterSpacing: 1.5,
                        color: RiveroColors.textMuted,
                      ),
                    ),
                    Text(
                      '${bankAccounts.length} Active',
                      style: RiveroTypography.labelSmall.copyWith(
                        color: RiveroColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.sm),

                if (bankAccounts.isEmpty)
                  RiveroCard(
                    child: Center(
                      child: Text(
                        'No custodial bank accounts added yet.',
                        style: RiveroTypography.bodySmall,
                      ),
                    ),
                  )
                else
                  ...bankAccounts.map((account) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
                      child: RiveroCard(
                        onTap: () =>
                            CreateAccountSheet.show(context, existing: account),
                        child: Row(
                          children: [
                            BankBadge(name: account.institution),
                            const SizedBox(width: RiveroSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    account.name,
                                    style: RiveroTypography.bodyLarge,
                                  ),
                                  Text(
                                    '${account.institution} '
                                    '••${account.accountMask}',
                                    style: RiveroTypography.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: RiveroSpacing.sm),
                            Text(
                              isPrivacy
                                  ? '••••'
                                  : CurrencyFormatter.format(
                                      account.balanceMinorUnits,
                                    ),
                              style: RiveroTypography.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: RiveroSpacing.md),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    key: const ValueKey('add-account'),
                    onPressed: () => CreateAccountSheet.show(context),
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add account or card'),
                  ),
                ),
                const SizedBox(height: RiveroSpacing.huge),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.amountMinorUnits,
    required this.color,
    required this.isPrivacy,
  });

  final String label;
  final int amountMinorUnits;
  final Color color;
  final bool isPrivacy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: RiveroSpacing.xs),
            Text(label, style: RiveroTypography.bodySmall),
          ],
        ),
        const SizedBox(height: 2),
        if (isPrivacy)
          Text('••••••••', style: RiveroTypography.bodyMedium)
        else
          Text(
            CurrencyFormatter.format(amountMinorUnits),
            style: RiveroTypography.titleMedium.copyWith(
              color: RiveroColors.textPrimary,
              fontSize: 14,
            ),
          ),
      ],
    );
  }
}
