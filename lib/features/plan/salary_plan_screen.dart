import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Split a month's salary across buckets. Expense takes whatever is left, so
/// the split can never exceed the salary. Set a bucket to 0 to skip it.
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

  Future<void> _apply(int salary, Map<String, int> split) async {
    setState(() => _saving = true);
    await ref
        .read(salaryPlanServiceProvider)
        .apply(
          salary: salary,
          allocations: split,
          salaryTransactionId: widget.salaryTransaction?.id,
          rememberAsDefault: _remember,
        );
    if (ref.read(monthlySalaryProvider) == 0) {
      ref.read(monthlySalaryProvider.notifier).state = salary;
    }
    ref.invalidate(pendingSalaryProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final buckets = ref.watch(allAllocationBucketsProvider).value ?? const [];
    final salary = parseAmountMinorUnits(_salary.text);
    final expense = buckets
        .where((b) => b.role == AccountRole.expense)
        .toList();
    final others = buckets.where((b) => b.role != AccountRole.expense).toList()
      ..sort((a, b) => a.priorityOrder.compareTo(b.priorityOrder));

    final split = <String, int>{
      for (final b in others) b.id: parseAmountMinorUnits(_field(b).text),
    };
    final othersTotal = split.values.fold<int>(0, (a, b) => a + b);
    final remaining = salary - othersTotal;
    final over = remaining < 0;
    if (expense.isNotEmpty) split[expense.first.id] = over ? 0 : remaining;

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Salary plan',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(RiveroSpacing.lg),
        children: [
          RiveroCard(
            isElevated: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.salaryTransaction == null
                      ? 'MONTHLY SALARY'
                      : 'SALARY RECEIVED',
                  style: RiveroTypography.labelSmall.copyWith(
                    letterSpacing: 1.5,
                  ),
                ),
                TextField(
                  key: const ValueKey('salary-field'),
                  controller: _salary,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: RiveroTypography.financialLarge,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixText: '₹',
                    border: InputBorder.none,
                    hintText: '0',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: RiveroSpacing.xl),
          Text(
            'WHERE IT GOES',
            style: RiveroTypography.labelSmall.copyWith(letterSpacing: 1.5),
          ),
          const SizedBox(height: RiveroSpacing.sm),
          for (final b in others)
            Padding(
              padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
              child: RiveroCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: RiveroSpacing.lg,
                  vertical: RiveroSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(b.name, style: RiveroTypography.titleMedium),
                    ),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        key: ValueKey('plan-${b.id}'),
                        controller: _field(b),
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixText: '₹',
                          border: InputBorder.none,
                          hintText: '0 (skip)',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          RiveroCard(
            borderColor: over ? RiveroColors.danger : null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.isEmpty ? 'Left over' : expense.first.name,
                        style: RiveroTypography.titleMedium,
                      ),
                      Text(
                        over ? 'Plan exceeds salary' : 'The rest goes here',
                        style: RiveroTypography.bodySmall.copyWith(
                          color: over ? RiveroColors.danger : null,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  CurrencyFormatter.format(remaining),
                  key: const ValueKey('plan-rest'),
                  style: RiveroTypography.financialMedium.copyWith(
                    color: over ? RiveroColors.danger : null,
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use this split every month'),
            subtitle: const Text('Turn off to skip or change just this month'),
            value: _remember,
            onChanged: (v) => setState(() => _remember = v),
          ),
          const SizedBox(height: RiveroSpacing.md),
          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                backgroundColor: RiveroColors.textPrimary,
                foregroundColor: RiveroColors.background,
              ),
              onPressed: salary == 0 || over || _saving
                  ? null
                  : () => _apply(salary, split),
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}
