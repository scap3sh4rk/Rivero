import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/currency/currency.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/account_color.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/accounts/widgets/create_account_sheet.dart';
import 'package:rivero/features/settings/screens/categories_screen.dart';
import 'package:rivero/features/transactions/widgets/activity_row.dart';

/// One account or card: its balance, the autopays charged to it, and every
/// transaction made with it.
class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({required this.accountId, super.key});

  final String accountId;

  static Future<void> open(BuildContext context, String accountId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AccountDetailScreen(accountId: accountId),
        ),
      );

  Future<void> _updateBalance(
    BuildContext context,
    WidgetRef ref,
    PhysicalAccount a,
  ) async {
    final current = a.isLiability ? -a.balanceMinorUnits : a.balanceMinorUnits;
    String shown(int v) => v % 100 == 0
        ? '${v ~/ 100}'
        : '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';
    final controller = TextEditingController(
      text: current > 0 ? shown(current) : '',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.isLiability ? 'Amount outstanding' : 'Current balance'),
        content: TextField(
          key: const ValueKey('balance-field'),
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: '₹',
            helperText: a.isLiability
                ? 'What you owe on this card right now'
                : 'What the account shows right now',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, parseAmountMinorUnits(controller.text)),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    // Not disposed here: the dialog is still animating out and uses it.
    if (value == null) return;
    await ref
        .read(ledgerServiceProvider)
        .setBalance(a.id, a.isLiability ? -value : value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account =
        (ref.watch(activePhysicalAccountsProvider).value ?? const [])
            .where((a) => a.id == accountId)
            .firstOrNull;
    if (account == null) {
      // Removed (or still loading): nothing to show.
      return Scaffold(
        backgroundColor: RiveroColors.background,
        appBar: RiveroAppBar(
          title: '',
          showProfile: false,
          leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        ),
      );
    }
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final txns = (ref.watch(allTransactionsStreamProvider).value ?? const [])
        .where((t) => t.physicalAccountId == accountId)
        .toList();
    final mandates = (ref.watch(allMandatesProvider).value ?? const [])
        .where(
          (m) =>
              m.physicalAccountId == accountId &&
              m.status == MandateStatus.active,
        )
        .toList();
    final categories = ref.watch(logCategoriesProvider);
    final tint = accountColor(account);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: account.name,
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: [
          IconButton(
            key: const ValueKey('update-balance'),
            tooltip: 'Update balance',
            onPressed: () => _updateBalance(context, ref, account),
            icon: const Icon(Icons.edit_note_rounded),
          ),
          IconButton(
            tooltip: 'Edit account',
            onPressed: () =>
                CreateAccountSheet.show(context, existing: account),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge,
        ),
        children: [
          RiveroCard(
            isElevated: true,
            borderColor: tint.withValues(alpha: 0.5),
            padding: const EdgeInsets.all(RiveroSpacing.xl),
            child: Row(
              children: [
                BankBadge(
                  name: account.institution,
                  color: tint,
                  imagePath: account.imagePath,
                  size: 52,
                ),
                const SizedBox(width: RiveroSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.isLiability ? 'Outstanding' : 'Balance',
                        style: RiveroTypography.bodySmall,
                      ),
                      Text(
                        accountMoney(
                          account,
                          account.isLiability
                              ? account.balanceMinorUnits.abs()
                              : account.balanceMinorUnits,
                          money,
                        ),
                        style: RiveroTypography.financialLarge,
                      ),
                      Text(
                        '${account.institution} ••${account.accountMask}'
                        ' · ${account.accountType}',
                        style: RiveroTypography.bodySmall,
                      ),
                      if (account.isLiability &&
                          account.creditLimitMinorUnits > 0)
                        Text(
                          '${money(account.creditLimitMinorUnits)} limit',
                          style: RiveroTypography.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (mandates.isNotEmpty) ...[
            const SizedBox(height: RiveroSpacing.xl),
            Text(
              'Autopay on this account',
              style: RiveroTypography.titleMedium,
            ),
            const SizedBox(height: RiveroSpacing.sm),
            for (final m in mandates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: BankBadge(name: m.payee, size: 36, circle: true),
                title: Text(m.payee),
                subtitle: m.nextExecutionDate == null
                    ? null
                    : Text(
                        'Next ${DateFormat('d MMM').format(m.nextExecutionDate!)}',
                      ),
                trailing: Text(
                  money(
                    m.isVariableAmount
                        ? (m.maxCapMinorUnits ?? m.amountMinorUnits)
                        : m.amountMinorUnits,
                  ),
                ),
              ),
          ],
          const SizedBox(height: RiveroSpacing.xl),
          Text(
            txns.isEmpty ? 'No transactions yet' : 'Transactions',
            style: RiveroTypography.titleMedium,
          ),
          for (final t in txns)
            ActivityRow(
              t,
              privacy: privacy,
              tint: t.amountMinorUnits > 0
                  ? RiveroColors.success
                  : categoryColor(t.category, categories),
            ),
        ],
      ),
    );
  }
}

/// Where the net worth figure comes from.
class NetWorthSheet extends ConsumerWidget {
  const NetWorthSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RiveroColors.surface,
    builder: (_) => const NetWorthSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts =
        ref.watch(activePhysicalAccountsProvider).value ?? const [];
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final assets = accounts.where((a) => !a.isLiability).toList();
    final cards = accounts.where((a) => a.isLiability).toList();
    // Totals in rupees (other currencies at the user's rate).
    final rates = ref.watch(exchangeRatesProvider);
    final assetTotal = rates
        .inHome(assets)
        .fold<int>(0, (s, a) => s + a.balanceMinorUnits);
    final debt = rates
        .inHome(cards)
        .fold<int>(
          0,
          (s, a) => s + (a.balanceMinorUnits < 0 ? -a.balanceMinorUnits : 0),
        );
    final owed = (ref.watch(duesProvider).value ?? const [])
        .where((d) => d.status == DueStatus.open)
        .fold<int>(0, (s, d) => s + d.amountMinorUnits - d.receivedMinorUnits);

    Widget line(PhysicalAccount a, {bool negative = false}) => ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: ColorDot(accountColor(a)),
      title: Text(a.name),
      trailing: Text(
        negative
            ? '− ${accountMoney(a, a.balanceMinorUnits.abs(), money)}'
            : accountMoney(a, a.balanceMinorUnits, money),
      ),
      onTap: () {
        Navigator.pop(context);
        AccountDetailScreen.open(context, a.id);
      },
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(RiveroSpacing.xl),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Net worth', style: RiveroTypography.bodyMedium),
              Text(
                money(assetTotal - debt),
                key: const ValueKey('networth-total'),
                style: RiveroTypography.financialLarge,
              ),
              const SizedBox(height: RiveroSpacing.lg),
              Text(
                'Bank & cash · ${money(assetTotal)}',
                style: RiveroTypography.titleMedium,
              ),
              for (final a in assets) line(a),
              if (cards.isNotEmpty) ...[
                const SizedBox(height: RiveroSpacing.md),
                Text(
                  'Card dues · − ${money(debt)}',
                  style: RiveroTypography.titleMedium,
                ),
                for (final a in cards) line(a, negative: true),
              ],
              if (owed > 0) ...[
                const SizedBox(height: RiveroSpacing.md),
                Text(
                  'Not included: ${money(owed)} owed to you',
                  style: RiveroTypography.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
