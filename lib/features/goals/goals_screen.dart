import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/domain/account_group.dart';
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
        ..watch(activePhysicalAccountsProvider)
        ..watch(exchangeRatesProvider);
      final goals = Goals(ref.watch(databaseProvider));
      return [for (final g in await goals.load()) await goals.progress(g)];
    });

String _rupees(int minor) => minor % 100 == 0
    ? '${minor ~/ 100}'
    : '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

/// The ring: how far along a goal is (display only; amounts stay integers).
class GoalRing extends StatelessWidget {
  const GoalRing(this.p, {super.key, this.size = 52});

  final GoalProgress p;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = p.goal.targetMinorUnits;
    final value = t == 0 ? 1.0 : (p.savedMinorUnits / t).clamp(0.0, 1.0);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: size / 9,
              backgroundColor: RiveroColors.surfaceInteractive,
              color: p.reached ? RiveroColors.success : RiveroColors.accent,
            ),
          ),
          Text(
            '${(value * 100).floor()}%',
            style: RiveroTypography.labelSmall.copyWith(
              color: RiveroColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// "On track · ₹4,000 a month", "Behind by ₹2,000 · …", or "Reached".
String goalStatus(GoalProgress p, String Function(int) money) => p.reached
    ? 'Reached'
    : p.behindByMinorUnits > 0
    ? 'Behind by ${money(p.behindByMinorUnits)} · '
          '${money(p.perMonthMinorUnits)} a month to catch up'
    : 'On track · ${money(p.perMonthMinorUnits)} a month';

Color? goalStatusColor(GoalProgress p) => p.reached
    ? RiveroColors.success
    : p.behindByMinorUnits > 0
    ? RiveroColors.warning
    : null;

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const GoalsScreen()));

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
        onPressed: () => GoalEditor.open(context),
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
                      'No goals yet. Tap + to save towards something, like a '
                      'car by June. Count your FDs, accounts, cash, stocks '
                      'or gold towards it, and Rivero keeps track.',
                      style: RiveroTypography.bodyMedium,
                    ),
                  ),
                for (final p in list)
                  Padding(
                    key: ValueKey('goal-${p.goal.id}'),
                    padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
                    child: RiveroCard(
                      onTap: () => GoalEditor.open(context, existing: p.goal),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GoalRing(p),
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
                                      goalStatus(p, money),
                                      style: RiveroTypography.bodySmall
                                          .copyWith(color: goalStatusColor(p)),
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
                          if (p.parts.isNotEmpty) ...[
                            const SizedBox(height: RiveroSpacing.sm),
                            Wrap(
                              spacing: RiveroSpacing.xs,
                              runSpacing: RiveroSpacing.xs,
                              children: [
                                for (final part in p.parts)
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      '${part.name} ${money(part.value)}',
                                      style: RiveroTypography.labelSmall,
                                    ),
                                  ),
                              ],
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(
                                top: RiveroSpacing.sm,
                              ),
                              child: Text(
                                'Tap to choose what counts towards it',
                                style: RiveroTypography.bodySmall,
                              ),
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

/// Create or edit a goal: name, amount, date, and what counts towards it.
/// Deleting lives here (with a confirmation), never one tap away on a card.
class GoalEditor extends ConsumerStatefulWidget {
  const GoalEditor({super.key, this.existing});

  final Goal? existing;

  static Future<void> open(BuildContext context, {Goal? existing}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => GoalEditor(existing: existing)),
      );

  @override
  ConsumerState<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<GoalEditor> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _target = TextEditingController(
    text: widget.existing == null
        ? ''
        : _rupees(widget.existing!.targetMinorUnits),
  );
  late DateTime _by =
      widget.existing?.by ??
      DateTime(DateTime.now().year + 1, DateTime.now().month);
  late final List<GoalSource> _sources = [...?widget.existing?.sources];

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final target = parseAmountMinorUnits(_target.text.trim());
    if (_name.text.trim().isEmpty || target <= 0) return;
    final now = DateTime.now();
    final old = widget.existing;
    final g = Goal(
      id: old?.id ?? 'goal-${now.microsecondsSinceEpoch}',
      name: _name.text.trim(),
      targetMinorUnits: target,
      by: _by,
      start: old?.start ?? DateTime(now.year, now.month, now.day),
      sources: [..._sources],
    );
    await Goals(ref.read(databaseProvider)).put(g);
    ref.invalidate(goalsProvider);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final g = widget.existing;
    if (g == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${g.name}"?'),
        content: const Text(
          'Only the goal goes. Your accounts, FDs and money are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const ValueKey('goal-delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: RiveroColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final goals = Goals(ref.read(databaseProvider));
    await goals.remove(g.id);
    ref.invalidate(goalsProvider);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // The editor closes now; Undo works on the app-wide providers.
    final container = ProviderScope.containerOf(context);
    Navigator.pop(context);
    // A last chance: bring it back as it was.
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted "${g.name}"'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await goals.put(g);
            container.invalidate(goalsProvider);
          },
        ),
      ),
    );
  }

  Future<void> _addSource() async {
    final accounts = (ref.read(activePhysicalAccountsProvider).value ?? [])
        .where((a) => !a.isLiability)
        .toList();
    final buckets = (ref.read(allAllocationBucketsProvider).value ?? [])
        .where((b) => b.role != AccountRole.expense)
        .toList();
    final have = {
      for (final s in _sources)
        if (s.id != null) '${s.kind.name}:${s.id}',
    };
    final picked = await showModalBottomSheet<GoalSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RiveroColors.surface,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(RiveroSpacing.lg),
            children: [
              Text(
                'What counts towards it?',
                style: RiveroTypography.titleLarge,
              ),
              const SizedBox(height: RiveroSpacing.sm),
              ListTile(
                key: const ValueKey('source-asset'),
                leading: const Icon(Icons.diamond_outlined),
                title: const Text('Cash, stocks, gold or anything else'),
                subtitle: const Text('You say what it is worth'),
                onTap: () => Navigator.pop(ctx, const GoalSource.asset('', 0)),
              ),
              if (accounts.isNotEmpty) ...[
                const Divider(),
                Text(
                  'Accounts and deposits',
                  style: RiveroTypography.bodySmall,
                ),
                for (final a in accounts)
                  if (!have.contains('account:${a.id}'))
                    ListTile(
                      key: ValueKey('source-account-${a.id}'),
                      leading: Icon(
                        AccountGroup.isFixedDeposit(a)
                            ? Icons.lock_clock_outlined
                            : AccountGroup.of(a) == AccountGroup.investment
                            ? Icons.trending_up_rounded
                            : Icons.account_balance_outlined,
                      ),
                      title: Text(a.name),
                      subtitle: Text(AccountGroup.of(a).label),
                      onTap: () => Navigator.pop(ctx, GoalSource.account(a.id)),
                    ),
              ],
              if (buckets.isNotEmpty) ...[
                const Divider(),
                Text(
                  'What you pay into a plan category from now on',
                  style: RiveroTypography.bodySmall,
                ),
                for (final b in buckets)
                  if (!have.contains('bucket:${b.id}'))
                    ListTile(
                      leading: const Icon(Icons.pie_chart_outline_rounded),
                      title: Text(b.name),
                      onTap: () => Navigator.pop(ctx, GoalSource.bucket(b.id)),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.kind == GoalSourceKind.asset) {
      final asset = await _editAsset(null);
      if (asset != null) setState(() => _sources.add(asset));
    } else {
      setState(() => _sources.add(picked));
    }
  }

  /// Name and value of a cash / stocks / gold entry.
  Future<GoalSource?> _editAsset(GoalSource? old) => showDialog<GoalSource>(
    context: context,
    builder: (_) => _AssetDialog(old),
  );

  String _sourceName(GoalSource s) {
    switch (s.kind) {
      case GoalSourceKind.asset:
        return s.label!;
      case GoalSourceKind.account:
        return (ref.read(activePhysicalAccountsProvider).value ?? [])
                .where((a) => a.id == s.id)
                .firstOrNull
                ?.name ??
            'Removed account';
      case GoalSourceKind.bucket:
        final name = (ref.read(allAllocationBucketsProvider).value ?? [])
            .where((b) => b.id == s.id)
            .firstOrNull
            ?.name;
        return 'Paid into ${name ?? 'a removed category'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..watch(activePhysicalAccountsProvider)
      ..watch(allAllocationBucketsProvider);
    final target = parseAmountMinorUnits(_target.text.trim());
    final ok = _name.text.trim().isNotEmpty && target > 0;
    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: widget.existing == null ? 'New goal' : 'Edit goal',
        showProfile: false,
        leading: const CloseButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(RiveroSpacing.xl),
        children: [
          TextField(
            key: const ValueKey('goal-name'),
            controller: _name,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Goal'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: RiveroSpacing.field),
          TextField(
            key: const ValueKey('goal-target'),
            controller: _target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
            ],
            decoration: const InputDecoration(labelText: 'Amount ₹'),
            onChanged: (_) => setState(() {}),
          ),
          ListTile(
            key: const ValueKey('goal-by'),
            contentPadding: EdgeInsets.zero,
            title: const Text('By'),
            trailing: Text(DateFormat('d MMM yyyy').format(_by)),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _by.isBefore(now) ? now : _by,
                firstDate: _by.isBefore(now) ? _by : now,
                lastDate: DateTime(now.year + 30),
              );
              if (d != null) setState(() => _by = d);
            },
          ),
          const SizedBox(height: RiveroSpacing.lg),
          Text('What counts towards it', style: RiveroTypography.titleMedium),
          Text(
            'Any mix: FDs (with interest so far), accounts, demat, what you '
            'pay into a plan category, and cash, stocks or gold you value.',
            style: RiveroTypography.bodySmall,
          ),
          const SizedBox(height: RiveroSpacing.sm),
          for (var i = 0; i < _sources.length; i++)
            Card(
              key: ValueKey('source-$i'),
              margin: const EdgeInsets.only(bottom: RiveroSpacing.xs),
              color: RiveroColors.surface,
              child: ListTile(
                leading: Icon(switch (_sources[i].kind) {
                  GoalSourceKind.account => Icons.account_balance_outlined,
                  GoalSourceKind.bucket => Icons.pie_chart_outline_rounded,
                  GoalSourceKind.asset => Icons.diamond_outlined,
                }),
                title: Text(_sourceName(_sources[i])),
                subtitle: _sources[i].kind == GoalSourceKind.asset
                    ? Text(
                        '${CurrencyFormatter.format(_sources[i].valueMinorUnits)}'
                        ' · tap to update',
                      )
                    : null,
                onTap: _sources[i].kind == GoalSourceKind.asset
                    ? () async {
                        final s = await _editAsset(_sources[i]);
                        if (s != null) setState(() => _sources[i] = s);
                      }
                    : null,
                trailing: IconButton(
                  tooltip: 'Stop counting this',
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: () => setState(() => _sources.removeAt(i)),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('goal-add-source'),
              onPressed: _addSource,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
          ),
          const SizedBox(height: RiveroSpacing.xl),
          FilledButton(
            key: const ValueKey('goal-save'),
            onPressed: ok ? _save : null,
            child: const Text('Save'),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: RiveroSpacing.md),
            Center(
              child: TextButton(
                key: const ValueKey('goal-delete'),
                onPressed: _delete,
                child: const Text(
                  'Delete goal',
                  style: TextStyle(color: RiveroColors.danger),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks what an asset is and what it is worth now.
class _AssetDialog extends StatefulWidget {
  const _AssetDialog(this.old);

  final GoalSource? old;

  @override
  State<_AssetDialog> createState() => _AssetDialogState();
}

class _AssetDialogState extends State<_AssetDialog> {
  late final _label = TextEditingController(text: widget.old?.label);
  late final _value = TextEditingController(
    text: widget.old == null ? '' : _rupees(widget.old!.valueMinorUnits),
  );

  @override
  void dispose() {
    _label.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.old == null ? 'Add something you own' : 'Update value'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('asset-label'),
          controller: _label,
          autofocus: widget.old == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What is it?',
            hintText: 'Cash at home, Infosys shares, gold',
          ),
        ),
        const SizedBox(height: RiveroSpacing.field),
        TextField(
          key: const ValueKey('asset-value'),
          controller: _value,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Worth now (₹)',
            helperText: 'Update it when the value changes',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('asset-save'),
        onPressed: () {
          final v = parseAmountMinorUnits(_value.text.trim());
          if (_label.text.trim().isEmpty || v < 0) return;
          Navigator.pop(context, GoalSource.asset(_label.text.trim(), v));
        },
        child: const Text('Save'),
      ),
    ],
  );
}
