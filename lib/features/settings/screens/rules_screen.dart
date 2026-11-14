import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/rules/capture_rules.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_fab.dart';

/// Settings → Rules: "when it contains X, put it in Y (or ignore it)".
class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const RulesScreen()));

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  List<CaptureRule>? _rules;

  CaptureRules get _store => CaptureRules(ref.read(databaseProvider));

  @override
  void initState() {
    super.initState();
    _store.load().then((r) {
      if (mounted) setState(() => _rules = r);
    });
  }

  Future<void> _save(List<CaptureRule> rules) async {
    setState(() => _rules = rules);
    await _store.save(rules);
  }

  Future<void> _edit({CaptureRule? initial, int? index}) async {
    final rule = await showRuleDialog(context, ref, initial: initial);
    if (rule == null) return;
    final list = [...?_rules];
    index == null ? list.add(rule) : list[index] = rule;
    await _save(list);
  }

  static String describe(CaptureRule r) {
    final range = [
      if (r.minMinorUnits != null)
        'from ${CurrencyFormatter.format(r.minMinorUnits!)}',
      if (r.maxMinorUnits != null)
        'up to ${CurrencyFormatter.format(r.maxMinorUnits!)}',
    ].join(' ');
    return '${r.ignore ? 'Ignore it' : 'Put in ${r.category}'}'
        '${range.isEmpty ? '' : ' · $range'}';
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Rules',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      floatingActionButton: RiveroFab(tooltip: 'Add rule', onPressed: _edit),
      body: rules == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.sm),
              children: [
                Padding(
                  padding: const EdgeInsets.all(RiveroSpacing.lg),
                  child: Text(
                    'Rules sort captured payments for you. The first rule '
                    'that matches wins; you still see each payment before '
                    'it counts.',
                    style: RiveroTypography.bodySmall,
                  ),
                ),
                if (rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(RiveroSpacing.lg),
                    child: Text(
                      'No rules yet. Tap + to add one, for example: '
                      'contains "Swiggy" → Food.',
                      style: RiveroTypography.bodyMedium,
                    ),
                  ),
                for (var i = 0; i < rules.length; i++)
                  ListTile(
                    key: ValueKey('rule-$i'),
                    title: Text('Contains "${rules[i].contains}"'),
                    subtitle: Text(describe(rules[i])),
                    onTap: () => _edit(initial: rules[i], index: i),
                    trailing: IconButton(
                      tooltip: 'Remove rule',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => _save([...rules]..removeAt(i)),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Asks for a rule; [initial] pre-fills it (used by the
/// "make a rule" suggestion after re-categorising).
Future<CaptureRule?> showRuleDialog(
  BuildContext context,
  WidgetRef ref, {
  CaptureRule? initial,
}) => showDialog<CaptureRule>(
  context: context,
  builder: (_) => _RuleDialog(
    initial: initial,
    categories: ref.read(logCategoriesProvider).map((c) => c.name).toList(),
  ),
);

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.categories, this.initial});

  final CaptureRule? initial;
  final List<String> categories;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final _contains = TextEditingController(text: widget.initial?.contains);
  late final _min = TextEditingController(
    text: _money(widget.initial?.minMinorUnits),
  );
  late final _max = TextEditingController(
    text: _money(widget.initial?.maxMinorUnits),
  );
  late String? _category =
      widget.initial?.category ?? widget.categories.firstOrNull;
  late bool _ignore = widget.initial?.ignore ?? false;

  static String _money(int? m) => m == null
      ? ''
      : (m % 100 == 0
            ? '${m ~/ 100}'
            : '${m ~/ 100}.${(m % 100).toString().padLeft(2, '0')}');

  @override
  void dispose() {
    _contains.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  int? _amount(TextEditingController c) =>
      c.text.trim().isEmpty ? null : parseAmountMinorUnits(c.text.trim());

  @override
  Widget build(BuildContext context) {
    final amountField = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
    ];
    final ok =
        _contains.text.trim().isNotEmpty && (_ignore || _category != null);
    return AlertDialog(
      title: Text(widget.initial == null ? 'New rule' : 'Edit rule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('rule-contains'),
              controller: _contains,
              autofocus: widget.initial == null,
              decoration: const InputDecoration(
                labelText: 'When the payee or message contains',
                hintText: 'Swiggy',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: RiveroSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('rule-min'),
                    controller: _min,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: amountField,
                    decoration: const InputDecoration(
                      labelText: 'From ₹ (optional)',
                    ),
                  ),
                ),
                const SizedBox(width: RiveroSpacing.sm),
                Expanded(
                  child: TextField(
                    key: const ValueKey('rule-max'),
                    controller: _max,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: amountField,
                    decoration: const InputDecoration(
                      labelText: 'Up to ₹ (optional)',
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              key: const ValueKey('rule-ignore'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Ignore it'),
              subtitle: const Text('Not a payment to track'),
              value: _ignore,
              onChanged: (v) => setState(() => _ignore = v),
            ),
            if (!_ignore) ...[
              Text('Then put it in', style: RiveroTypography.bodySmall),
              const SizedBox(height: RiveroSpacing.xs),
              Wrap(
                spacing: RiveroSpacing.sm,
                runSpacing: RiveroSpacing.xs,
                children: [
                  for (final c in {...widget.categories, ?_category})
                    ChoiceChip(
                      key: ValueKey('rule-cat-$c'),
                      label: Text(c),
                      selected: _category == c,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('rule-save'),
          onPressed: ok
              ? () => Navigator.pop(
                  context,
                  CaptureRule(
                    contains: _contains.text.trim(),
                    category: _ignore ? null : _category,
                    ignore: _ignore,
                    minMinorUnits: _amount(_min),
                    maxMinorUnits: _amount(_max),
                  ),
                )
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
