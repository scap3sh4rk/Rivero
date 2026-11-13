import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
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
        subtitle: 'Custodial Balances & Credit Lines',
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
                          const Icon(
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
                      child: InkWell(
                        borderRadius: BorderRadius.circular(RiveroRadii.lg),
                        onLongPress: () =>
                            _confirmDeactivate(context, ref, account),
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
                      'CUSTODIAL ACCOUNTS',
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
                        padding: const EdgeInsets.all(RiveroSpacing.md),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: BankBadge(name: account.institution),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    account.name,
                                    style: RiveroTypography.titleMedium
                                        .copyWith(fontSize: 15),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: RiveroColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(
                                      RiveroRadii.xs,
                                    ),
                                  ),
                                  child: Text(
                                    account.accountType,
                                    style: RiveroTypography.labelSmall.copyWith(
                                      fontSize: 10,
                                      color: RiveroColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${account.institution} · ••${account.accountMask}',
                              style: RiveroTypography.bodySmall.copyWith(
                                fontSize: 12,
                              ),
                            ),
                            trailing: isPrivacy
                                ? Text(
                                    '••••••••',
                                    style: RiveroTypography.monoMedium,
                                  )
                                : Text(
                                    CurrencyFormatter.format(
                                      account.balanceMinorUnits,
                                    ),
                                    style: RiveroTypography.monoMedium.copyWith(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: RiveroColors.textPrimary,
                                    ),
                                  ),
                            onLongPress: () =>
                                _confirmDeactivate(context, ref, account),
                          ),
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 80), // bottom padding for FAB
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDeactivate(
    BuildContext context,
    WidgetRef ref,
    PhysicalAccount account,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: RiveroColors.surfaceElevated,
        title: Text('Deactivate Account?', style: RiveroTypography.titleMedium),
        content: Text(
          'Are you sure you want to archive "${account.name}"? Existing transactions will remain in ledger.',
          style: RiveroTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: RiveroColors.danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = ref.read(databaseProvider);
      await db.accountsDao.deactivatePhysicalAccount(account.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account "${account.name}" archived.'),
            backgroundColor: RiveroColors.expenseAccent,
          ),
        );
      }
    }
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
