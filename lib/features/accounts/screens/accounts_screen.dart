import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/credit_utilization.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/account_color.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/accounts/screens/account_detail_screen.dart';
import 'package:rivero/features/accounts/widgets/create_account_sheet.dart';

/// Accounts: net worth, then bank & cash and cards as short rows.
/// Long-press a row to drag it up or down; tap to open it.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts =
        ref.watch(activePhysicalAccountsProvider).value ?? const [];
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);
    final banks = accounts.where((a) => !a.isLiability).toList();
    final cards = accounts.where((a) => a.isLiability).toList();
    final bankTotal = banks.fold<int>(0, (s, a) => s + a.balanceMinorUnits);
    final debt = cards.fold<int>(
      0,
      (s, a) => s + (a.balanceMinorUnits < 0 ? -a.balanceMinorUnits : 0),
    );

    Future<void> reorder(List<PhysicalAccount> group, int from, int to) async {
      final ids = group.map((a) => a.id).toList();
      final moved = ids.removeAt(from);
      ids.insert(to > from ? to - 1 : to, moved);
      // Keep the other group's positions after this one's.
      final others = accounts
          .where((a) => !ids.contains(a.id))
          .map((a) => a.id);
      final dao = ref.read(databaseProvider).accountsDao;
      await dao.reorderAccounts(
        group.first.isLiability ? [...others, ...ids] : [...ids, ...others],
      );
    }

    Widget section(String title, List<PhysicalAccount> group) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: RiveroSpacing.xl,
            bottom: RiveroSpacing.sm,
          ),
          child: Text(title, style: RiveroTypography.titleMedium),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, _, _) => Material(
            color: Colors.transparent,
            elevation: 6,
            borderRadius: RiveroRadii.borderLg,
            child: child,
          ),
          onReorderStart: (_) => HapticFeedback.mediumImpact(),
          onReorder: (from, to) => reorder(group, from, to),
          children: [
            for (var i = 0; i < group.length; i++)
              ReorderableDelayedDragStartListener(
                key: ValueKey(group[i].id),
                index: i,
                child: _AccountRow(group[i], money: money),
              ),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Accounts',
        actions: [
          IconButton(
            tooltip: 'Add Account',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => CreateAccountSheet.show(context),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          RiveroCard(
            key: const ValueKey('networth-card'),
            onTap: () => NetWorthSheet.show(context),
            isElevated: true,
            padding: const EdgeInsets.all(RiveroSpacing.xl),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Net worth', style: RiveroTypography.bodyMedium),
                      Text(
                        money(bankTotal - debt),
                        style: RiveroTypography.financialLarge,
                      ),
                      Text(
                        'Bank ${money(bankTotal)}'
                        '${cards.isEmpty ? '' : ' · Cards −${money(debt)}'}',
                        style: RiveroTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: RiveroColors.textMuted,
                ),
              ],
            ),
          ),
          if (banks.isNotEmpty) section('Bank & cash', banks),
          if (cards.isNotEmpty) section('Cards', cards),
          const SizedBox(height: RiveroSpacing.lg),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              key: const ValueKey('add-account'),
              onPressed: () => CreateAccountSheet.show(context),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add account or card'),
            ),
          ),
          if (accounts.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: RiveroSpacing.md),
              child: Center(
                child: Text(
                  'Long-press an account to reorder',
                  style: RiveroTypography.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A bank/cash account or a credit card, with what matters for each.
class _AccountRow extends StatelessWidget {
  const _AccountRow(this.a, {required this.money});

  final PhysicalAccount a;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) {
    final tint = accountColor(a);
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.md),
      child: RiveroCard(
        padding: const EdgeInsets.all(RiveroSpacing.xl),
        onTap: () => AccountDetailScreen.open(context, a.id),
        child: a.isLiability
            ? _cardBody(tint)
            : Row(
                children: [
                  BankBadge(
                    name: a.institution,
                    color: tint,
                    imagePath: a.imagePath,
                    size: 48,
                  ),
                  const SizedBox(width: RiveroSpacing.md),
                  Expanded(child: _identity()),
                  const SizedBox(width: RiveroSpacing.sm),
                  Text(
                    money(a.balanceMinorUnits),
                    style: RiveroTypography.financialMedium,
                  ),
                ],
              ),
      ),
    );
  }

  /// Name, then bank ••mask · type: which account this is at a glance.
  Widget _identity() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        a.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: RiveroTypography.titleMedium,
      ),
      const SizedBox(height: 2),
      Text(
        '${a.institution} ••${a.accountMask} · ${a.accountType}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: RiveroTypography.bodySmall,
      ),
    ],
  );

  Widget _cardBody(Color tint) {
    final u = CreditUtilization.fromBalance(
      creditLimitMinorUnits: a.creditLimitMinorUnits,
      balanceMinorUnits: a.balanceMinorUnits,
    );
    final hasLimit = u.creditLimitMinorUnits > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            BankBadge(
              name: a.institution,
              color: tint,
              imagePath: a.imagePath,
              size: 48,
            ),
            const SizedBox(width: RiveroSpacing.md),
            Expanded(child: _identity()),
          ],
        ),
        const SizedBox(height: RiveroSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Outstanding', style: RiveroTypography.bodySmall),
                  Text(
                    money(u.usedMinorUnits),
                    style: RiveroTypography.financialMedium,
                  ),
                ],
              ),
            ),
            if (hasLimit)
              Container(
                key: ValueKey('usage-${a.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: RiveroSpacing.md,
                  vertical: RiveroSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: u.statusColor.withValues(alpha: 0.15),
                  borderRadius: RiveroRadii.borderFull,
                  border: Border.all(
                    color: u.statusColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  u.pillLabel,
                  style: RiveroTypography.labelLarge.copyWith(
                    color: u.statusColor,
                  ),
                ),
              ),
          ],
        ),
        if (hasLimit) ...[
          const SizedBox(height: RiveroSpacing.md),
          _UsageBar(percent: u.utilizationPercent, color: u.statusColor),
          const SizedBox(height: RiveroSpacing.sm),
          Text(
            'Limit ${money(u.creditLimitMinorUnits)} · '
            'Available ${money(u.availableMinorUnits)}',
            style: RiveroTypography.bodySmall,
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: RiveroSpacing.sm),
            child: Text(
              'Add the card limit to see usage',
              style: RiveroTypography.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Usage bar with ticks at 10% and 30%, the two lines that matter.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.percent, required this.color});

  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        height: 10,
        child: Stack(
          children: [
            Positioned.fill(
              top: 2,
              bottom: 2,
              child: ClipRRect(
                borderRadius: RiveroRadii.borderFull,
                child: LinearProgressIndicator(
                  value: (percent / 100).clamp(0.0, 1.0),
                  backgroundColor: RiveroColors.surfaceInteractive,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            for (final mark in [0.10, 0.30])
              Positioned(
                left: c.maxWidth * mark - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: RiveroColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}
