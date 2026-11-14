import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Split a month's salary. Fixed categories (investments, savings, rent, ...)
/// come first; spending gets the rest, so the plan can never exceed salary.
class SalaryPlanScreen extends ConsumerStatefulWidget {
  const SalaryPlanScreen({super.key, this.salaryTransaction});

  /// The salary credit being split (null = planning from the expected salary).
  final LedgerTransaction? salaryTransaction;

  static Future<void> open(
    BuildContext context, {
    LedgerTransaction? salaryTransaction,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SalaryPlanScreen(salaryTransaction: salaryTransaction),
    ),
  );

  @override
  ConsumerState<SalaryPlanScreen> createState() => _SalaryPlanScreenState();
}

class _SalaryPlanScreenState extends ConsumerState<SalaryPlanScreen> {
  late final TextEditingController _salary;
  final _fields = <String, TextEditingController>{};
  bool _remember = true;
  bool _carry = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final tx = widget.salaryTransaction;
    final minor = tx != null
        ? tx.amountMinorUnits
        : ref.read(monthlySalaryProvider);
    _salary = TextEditingController(text: minor > 0 ? _rupees(minor) : '');
  }

  @override
  void dispose() {
    _salary.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _rupees(int minor) =>
      minor % 100 == 0 ? '${minor ~/ 100}' : (minor / 100).toStringAsFixed(2);

  TextEditingController _field(AllocationBucket b) => _fields.putIfAbsent(
    b.id,
    () => TextEditingController(
      text: (b.targetMinorUnits ?? 0) > 0 ? _rupees(b.targetMinorUnits!) : '',
    ),
  );

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );

  Future<void> _addCategory() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('cat-name'),
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Rent, Family, Loan EMI…',
              ),
            ),
            const SizedBox(height: RiveroSpacing.md),
            TextField(
              key: const ValueKey('cat-amount'),
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Every month',
                prefixText: '₹',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final id = await ref
          .read(salaryPlanServiceProvider)
          .addCustomCategory(name.text, parseAmountMinorUnits(amount.text));
      _fields[id] = TextEditingController(text: amount.text.trim());
      if (mounted) setState(() {});
    } on PlanValidationException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _remove(AllocationBucket b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${b.name}?'),
        content: const Text('Past transactions stay in your history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(salaryPlanServiceProvider).removeCategory(b.id);
    _fields.remove(b.id)?.dispose();
  }

  Future<void> _apply(int salary, Map<String, int> split) async {
    setState(() => _saving = true);
    await ref
        .read(salaryPlanServiceProvider)
        .apply(
          salary: salary,
          allocations: split,
          salaryTransactionId: widget.salaryTransaction?.id,
          cycleStart: ref.read(currentPaycycleProvider).cycleStartDate,
          rememberAsDefault: _remember,
          carryOver: _carry,
        );
    // Planning without a credit sets the expected salary; a real credit
    // updates it only when this split becomes the default.
    if (widget.salaryTransaction == null || _remember) {
      ref.read(monthlySalaryProvider.notifier).state = salary;
    }
    ref
      ..invalidate(pendingSalaryProvider)
      ..invalidate(awaitingSalaryProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final buckets = ref.watch(allAllocationBucketsProvider).value ?? const [];
    final privacy = ref.watch(privacyModeProvider);
    final salary = parseAmountMinorUnits(_salary.text);
    final spending = buckets
        .where((b) => b.role == AccountRole.expense)
        .firstOrNull;
    final fixed = buckets.where((b) => b.role != AccountRole.expense).toList()
      ..sort((a, b) => a.priorityOrder.compareTo(b.priorityOrder));

    final split = <String, int>{
      for (final b in fixed) b.id: parseAmountMinorUnits(_field(b).text),
    };
    final fixedTotal = split.values.fold<int>(0, (a, b) => a + b);
    final rest = salary - fixedTotal;
    final over = rest < 0;
    final carry = spending == null || !_carry
        ? 0
        : SalaryPlanService.carryFor(spending);
    if (spending != null) split[spending.id] = over ? 0 : rest;

    String money(int v) => privacy ? '••••' : CurrencyFormatter.format(v);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Salary plan',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          RiveroSpacing.sm,
          RiveroSpacing.xl,
          RiveroSpacing.huge,
        ),
        children: [
          Text(
            widget.salaryTransaction == null
                ? 'Monthly salary'
                : 'Salary received',
            style: RiveroTypography.bodyMedium,
          ),
          TextField(
            key: const ValueKey('salary-field'),
            controller: _salary,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: RiveroTypography.financialLarge,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixText: '₹',
              hintText: '0',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
          const SizedBox(height: RiveroSpacing.lg),
          Text('Set aside first', style: RiveroTypography.titleMedium),
          const SizedBox(height: RiveroSpacing.xs),
          Text(
            'Leave a category empty to skip it this month.',
            style: RiveroTypography.bodySmall,
          ),
          const SizedBox(height: RiveroSpacing.md),
          for (final b in fixed)
            _CategoryRow(
              key: ValueKey('row-${b.id}'),
              bucket: b,
              controller: _field(b),
              tooBig: salary > 0 && (split[b.id] ?? 0) > salary,
              onChanged: () => setState(() {}),
              onRemove: b.role == AccountRole.custom ? () => _remove(b) : null,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addCategory,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add category'),
            ),
          ),
          const SizedBox(height: RiveroSpacing.md),
          RiveroCard(
            borderColor: over ? RiveroColors.danger : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  over
                      ? 'This plan is ${money(-rest)} more than your salary'
                      : 'Left for spending',
                  style: RiveroTypography.bodyMedium.copyWith(
                    color: over ? RiveroColors.danger : null,
                  ),
                ),
                const SizedBox(height: RiveroSpacing.xs),
                Text(
                  over ? 'Reduce a category to continue' : money(rest),
                  key: const ValueKey('plan-rest'),
                  style: over
                      ? RiveroTypography.titleMedium
                      : RiveroTypography.financialMedium,
                ),
                if (!over && carry > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: RiveroSpacing.xs),
                    child: Text(
                      '+ ${money(carry)} unspent from last month',
                      style: RiveroTypography.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: RiveroSpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Carry over unspent money'),
            value: _carry,
            onChanged: (v) => setState(() => _carry = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use this split every month'),
            subtitle: const Text('Turn off to change only this month'),
            value: _remember,
            onChanged: (v) => setState(() => _remember = v),
          ),
          const SizedBox(height: RiveroSpacing.lg),
          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: salary == 0 || over || _saving
                  ? null
                  : () => _apply(salary, split),
              child: Text(salary == 0 ? 'Enter your salary' : 'Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.bucket,
    required this.controller,
    required this.tooBig,
    required this.onChanged,
    super.key,
    this.onRemove,
  });

  final AllocationBucket bucket;
  final TextEditingController controller;
  final bool tooBig;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: RiveroSpacing.md),
              child: Text(bucket.name, style: RiveroTypography.bodyLarge),
            ),
          ),
          const SizedBox(width: RiveroSpacing.md),
          SizedBox(
            width: 140,
            child: TextField(
              key: ValueKey('plan-${bucket.id}'),
              controller: controller,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                prefixText: '₹',
                hintText: 'Skip',
                errorText: tooBig ? 'Over salary' : null,
              ),
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove ${bucket.name}',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}
