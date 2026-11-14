import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/goals/goals.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/rivero_fab.dart';

/// Every goal with its progress, recomputed whenever money moves.
final AutoDisposeFutureProvider<List<GoalProgress>> goalsProvider =
    FutureProvider.autoDispose((ref) async {
      ref
        ..watch(allTransactionsStreamProvider)
        ..watch(activePhysicalAccountsProvider);
      final goals = Goals(ref.watch(databaseProvider));
      return [for (final g in await goals.load()) await goals.progress(g)];
    });

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const GoalsScreen()));

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final g = await showDialog<Goal>(
      context: context,
      builder: (_) => const _GoalDialog(),
    );
    if (g == null) return;
    final goals = Goals(ref.read(databaseProvider));
    await goals.save([...await goals.load(), g]);
    ref.invalidate(goalsProvider);
  }

  Future<void> _remove(WidgetRef ref, Goal g) async {
    final goals = Goals(ref.read(databaseProvider));
    await goals.save([
      for (final x in await goals.load())
        if (x.id != g.id) x,
    ]);
    ref.invalidate(goalsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(goalsProvider).value;
    final privacy = ref.watch(privacyModeProvider);
    String money(int v) => privacy ? '₹••••' : CurrencyFormatter.format(v);
    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Goals',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      floatingActionButton: RiveroFab(
        tooltip: 'Add goal',
        onPressed: () => _add(context, ref),
      ),
      body: list == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(RiveroSpacing.lg),
              children: [
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(RiveroSpacing.lg),
                    child: Text(
                      'No goals yet. Tap + to save towards something, like '
                      'a trip by June. Link it to an account or a plan '
                      'category and Rivero tracks it for you.',
                      style: RiveroTypography.bodyMedium,
                    ),
                  ),
                for (final p in list)
                  Padding(
                    key: ValueKey('goal-${p.goal.id}'),
                    padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
                    child: RiveroCard(
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 52,
                            child: CircularProgressIndicator(
                              // Display only: the amounts stay integers.
                              value: p.goal.targetMinorUnits == 0
                                  ? 1
                                  : (p.savedMinorUnits /
                                            p.goal.targetMinorUnits)
                                        .clamp(0, 1),
                              strokeWidth: 6,
                              backgroundColor: RiveroColors.surfaceElevated,
                              color: p.reached
                                  ? RiveroColors.success
                                  : RiveroColors.accent,
                            ),
                          ),
                          const SizedBox(width: RiveroSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.goal.name,
                                  style: RiveroTypography.titleMedium,
                                ),
                                Text(
                                  '${money(p.savedMinorUnits)} of '
                                  '${money(p.goal.targetMinorUnits)} · by '
                                  '${DateFormat('MMM yyyy').format(p.goal.by)}',
                                  style: RiveroTypography.bodySmall,
                                ),
                                Text(
                                  p.reached
                                      ? 'Reached'
                                      : p.behindByMinorUnits > 0
                                      ? 'Behind by ${money(p.behindByMinorUnits)}'
                                            ' · ${money(p.perMonthMinorUnits)} a month'
                                      : 'On track · ${money(p.perMonthMinorUnits)} a month',
                                  style: RiveroTypography.bodySmall.copyWith(
                                    color: p.reached
                                        ? RiveroColors.success
                                        : p.behindByMinorUnits > 0
                                        ? RiveroColors.warning
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove goal',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => _remove(ref, p.goal),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _GoalDialog extends ConsumerStatefulWidget {
  const _GoalDialog();

  @override
  ConsumerState<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends ConsumerState<_GoalDialog> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  late DateTime _by = DateTime(DateTime.now().year + 1, DateTime.now().month);

  /// `a:id` = an account, `b:id` = a plan category, null = none.
  String? _link;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = (ref.watch(activePhysicalAccountsProvider).value ?? [])
        .where((a) => !a.isLiability);
    final buckets = (ref.watch(allAllocationBucketsProvider).value ?? []).where(
      (b) => b.role != AccountRole.expense,
    );
    final target = parseAmountMinorUnits(_target.text.trim());
    final ok = _name.text.trim().isNotEmpty && target > 0;
    return AlertDialog(
      title: const Text('New goal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('goal-name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Goal'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const ValueKey('goal-target'),
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
              ],
              decoration: const InputDecoration(labelText: 'Amount ₹'),
              onChanged: (_) => setState(() {}),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('By'),
              trailing: Text(DateFormat('d MMM yyyy').format(_by)),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _by,
                  firstDate: now,
                  lastDate: DateTime(now.year + 30),
                );
                if (d != null) setState(() => _by = d);
              },
            ),
            DropdownButtonFormField<String?>(
              key: const ValueKey('goal-link'),
              initialValue: _link,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tracked by'),
              items: [
                const DropdownMenuItem(child: Text('Nothing yet')),
                for (final a in accounts)
                  DropdownMenuItem(
                    value: 'a:${a.id}',
                    child: Text('Balance of ${a.name}'),
                  ),
                for (final b in buckets)
                  DropdownMenuItem(
                    value: 'b:${b.id}',
                    child: Text('Paid into ${b.name}'),
                  ),
              ],
              onChanged: (v) => setState(() => _link = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('goal-save'),
          onPressed: ok
              ? () {
                  final now = DateTime.now();
                  Navigator.pop(
                    context,
                    Goal(
                      id: 'goal-${now.microsecondsSinceEpoch}',
                      name: _name.text.trim(),
                      targetMinorUnits: target,
                      start: DateTime(now.year, now.month, now.day),
                      by: _by,
                      accountId: _link?.startsWith('a:') == true
                          ? _link!.substring(2)
                          : null,
                      bucketId: _link?.startsWith('b:') == true
                          ? _link!.substring(2)
                          : null,
                    ),
                  );
                }
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
