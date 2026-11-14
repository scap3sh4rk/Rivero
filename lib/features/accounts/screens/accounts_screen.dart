import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
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
        padding: const EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge,
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

/// One account or card in a single calm row. Cards add a thin usage bar.
class _AccountRow extends StatelessWidget {
  const _AccountRow(this.a, {required this.money});

  final PhysicalAccount a;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) {
    final tint = accountColor(a);
    final owed = a.balanceMinorUnits < 0 ? -a.balanceMinorUnits : 0;
    final usage = a.isLiability && a.creditLimitMinorUnits > 0
        ? (owed / a.creditLimitMinorUnits).clamp(0.0, 1.0)
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
      child: RiveroCard(
        onTap: () => AccountDetailScreen.open(context, a.id),
        child: Column(
          children: [
            Row(
              children: [
                BankBadge(
                  name: a.institution,
                  color: tint,
                  imagePath: a.imagePath,
                  size: 40,
                ),
                const SizedBox(width: RiveroSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RiveroTypography.bodyLarge,
                      ),
                      Text(
                        '••${a.accountMask}',
                        style: RiveroTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  a.isLiability ? money(owed) : money(a.balanceMinorUnits),
                  style: RiveroTypography.titleMedium,
                ),
              ],
            ),
            if (usage != null) ...[
              const SizedBox(height: RiveroSpacing.sm),
              ClipRRect(
                borderRadius: RiveroRadii.borderFull,
                child: LinearProgressIndicator(
                  value: usage,
                  minHeight: 4,
                  backgroundColor: RiveroColors.surfaceInteractive,
                  // Score-friendly under 30% of the limit.
                  valueColor: AlwaysStoppedAnimation<Color>(
                    usage > 0.3 ? RiveroColors.warning : tint,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
