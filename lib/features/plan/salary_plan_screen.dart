import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/plan/plan_transfer_service.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/picker.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/rivero_fab.dart';

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

  // Where money goes (chosen here, saved on Apply).
  String? _salaryId;
  String? _spendingId;
  final Map<String, String?> _dest = {};

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

  /// Asked once per cycle, before any money moves: set up mid-month, the
  /// money may have moved already (and the balances entered show it).
  /// Returns null to cancel, true when it already moved.
  Future<bool?> _askAlreadyMoved(
    List<PlannedMove> moves,
    PhysicalAccount salaryAcc,
  ) {
    final total = moves.fold<int>(0, (t, m) => t + m.amount);
    final canMove = salaryAcc.balanceMinorUnits >= total;
    const f = CurrencyFormatter.format;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Has this month's money already moved?"),
        content: Text(
          canMove
              ? 'The plan moves ${f(total)} out of ${salaryAcc.name}. If you '
                    'already did that this month, choose Already moved: '
                    'nothing is moved again.'
              : '${salaryAcc.name} holds ${f(salaryAcc.balanceMinorUnits)}, '
                    'less than the ${f(total)} the plan moves, so it must '
                    'have moved already. Nothing is moved; it is marked done.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (canMove)
            TextButton(
              key: const ValueKey('move-now'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Move now'),
            ),
          FilledButton(
            key: const ValueKey('already-moved'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Already moved'),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(
    int salary,
    Map<String, int> split,
    List<PlannedMove> moves,
    PhysicalAccount? salaryAcc,
  ) async {
    final cycle = ref.read(currentPaycycleProvider);
    final credit = widget.salaryTransaction;
    // A salary that lands a few days early is next cycle's salary.
    final cycleStart = credit == null
        ? cycle.cycleStartDate
        : SalaryPlanService.cycleForSalary(cycle, credit.transactionTimestamp);
    final planService = ref.read(salaryPlanServiceProvider);
    var alreadyMoved = false;
    // A salary credit being split has just arrived: its money is there.
    // Already answered "already moved" for this cycle: not asked again.
    if (credit == null &&
        salaryAcc != null &&
        moves.isNotEmpty &&
        !await ref.read(planTransferServiceProvider).hasMoves(cycleStart) &&
        !await planService.movedOutside(cycleStart)) {
      final answer = await _askAlreadyMoved(moves, salaryAcc);
      if (answer == null) return;
      alreadyMoved = answer;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    if (_salaryId != null) {
      await ref.read(planTransferServiceProvider).setSalaryAccount(_salaryId!);
      ref.read(salaryAccountIdProvider.notifier).state = _salaryId;
    }
    await planService.setRouting(
      spendingAccountId: _spendingId,
      destinations: _dest,
    );
    try {
      await planService.apply(
        salary: salary,
        allocations: split,
        salaryTransactionId: widget.salaryTransaction?.id,
        cycleStart: cycleStart,
        rememberAsDefault: _remember,
        carryOver: _carry,
        // Applying the plan moves money between the accounts you track,
        // whether or not this cycle's salary was logged in Rivero.
        moveMoney: true,
        alreadyMoved: alreadyMoved,
      );
    } on PlanValidationException catch (e) {
      if (mounted) setState(() => _saving = false);
      _toast(e.message);
      return;
    }
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

    // --- how the plan routes money between accounts ---
    final accounts =
        (ref.watch(activePhysicalAccountsProvider).value ?? const [])
            .where((a) => !a.isLiability)
            .toList();
    final salaryAcc = PlanTransferService.salaryAccountOf(
      accounts,
      _salaryId ?? ref.watch(salaryAccountIdProvider),
    );
    final spendingAcc =
        accounts.where((a) => a.id == _spendingId).firstOrNull ??
        PlanTransferService.spendingAccountOf(buckets, accounts, salaryAcc);
    // An investment category with no account chosen goes to the one
    // investment account, if there is exactly one.
    for (final b in fixed) {
      if (_dest.containsKey(b.id) || b.linkedPhysicalAccountId != null) {
        continue;
      }
      final d = PlanTransferService.defaultDestination(
        b,
        accounts,
        salaryId: salaryAcc?.id,
        spendingId: spendingAcc?.id,
      );
      if (d != null) _dest[b.id] = d;
    }
    final effective = [
      for (final b in buckets)
        if (b.role != AccountRole.expense && _dest.containsKey(b.id))
          b.copyWith(linkedPhysicalAccountId: drift.Value(_dest[b.id]))
        else
          b,
    ];
    final transfers = ref.read(planTransferServiceProvider);
    final moves = salaryAcc == null
        ? const <PlannedMove>[]
        : transfers.movesFor(
            allocations: split,
            buckets: effective,
            salary: salaryAcc,
            spending: spendingAcc,
          );
    // Everything else in the plan is also paid out of the salary account,
    // just not into an account Rivero tracks (rent, family...).
    final planOnly = salaryAcc == null
        ? const <PlannedMove>[]
        : transfers.planOnly(
            allocations: split,
            buckets: effective,
            salary: salaryAcc,
          );
    final totalOut =
        moves.fold<int>(0, (t, m) => t + m.amount) +
        planOnly.fold<int>(0, (t, m) => t + m.amount);
    final short = salaryAcc == null
        ? 0
        : PlanTransferService.shortfall(salaryAcc, moves);
    String accountName(String? id) =>
        accounts.where((a) => a.id == id).firstOrNull?.name ??
        'Paid outside Rivero';

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Salary plan',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      floatingActionButton: RiveroFab(
        tooltip: 'Add category',
        onPressed: _addCategory,
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
          if (accounts.length > 1) ...[
            const SizedBox(height: RiveroSpacing.sm),
            PickerField<String>(
              label: 'Salary arrives in',
              value: salaryAcc?.id,
              options: [for (final a in accounts) PickerOption(a.id, a.name)],
              onChanged: (v) => setState(() => _salaryId = v),
            ),
            const SizedBox(height: RiveroSpacing.md),
            PickerField<String>(
              label: 'Spending money goes to',
              value: spendingAcc?.id,
              options: [for (final a in accounts) PickerOption(a.id, a.name)],
              onChanged: (v) => setState(() => _spendingId = v),
            ),
          ],
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
              destination: accounts.length > 1
                  ? accountName(
                      _dest.containsKey(b.id)
                          ? _dest[b.id]
                          : (b.linkedPhysicalAccountId == salaryAcc?.id
                                ? null
                                : b.linkedPhysicalAccountId),
                    )
                  : null,
              onPickDestination: () async {
                final current = _dest.containsKey(b.id)
                    ? _dest[b.id]
                    : b.linkedPhysicalAccountId;
                final picked = await showPicker<String>(
                  context,
                  title: '${b.name} goes to',
                  selected: current ?? '',
                  options: [
                    const PickerOption('', 'Paid outside Rivero'),
                    for (final a in accounts.where(
                      (a) => a.id != salaryAcc?.id,
                    ))
                      PickerOption(a.id, a.name),
                  ],
                );
                if (picked != null) {
                  setState(
                    () => _dest[b.id] = picked.value.isEmpty
                        ? null
                        : picked.value,
                  );
                }
              },
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
          if (salaryAcc != null &&
              (moves.isNotEmpty || planOnly.isNotEmpty)) ...[
            const SizedBox(height: RiveroSpacing.md),
            RiveroCard(
              key: const ValueKey('moves-card'),
              borderColor: short > 0 ? RiveroColors.warning : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Moves out of ${salaryAcc.name}',
                    style: RiveroTypography.titleMedium,
                  ),
                  const SizedBox(height: RiveroSpacing.sm),
                  for (final m in moves)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${m.name} → ${accountName(m.toAccountId)}',
                              style: RiveroTypography.bodyMedium,
                            ),
                          ),
                          Text(
                            money(m.amount),
                            style: RiveroTypography.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  for (final m in planOnly)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${m.name} → Paid outside Rivero',
                              style: RiveroTypography.bodyMedium,
                            ),
                          ),
                          Text(
                            money(m.amount),
                            style: RiveroTypography.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: RiveroSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total out of ${salaryAcc.name}',
                          style: RiveroTypography.titleMedium,
                        ),
                      ),
                      Text(
                        money(totalOut),
                        key: const ValueKey('moves-total'),
                        style: RiveroTypography.titleMedium,
                      ),
                    ],
                  ),
                  if (planOnly.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: RiveroSpacing.sm),
                      child: Text(
                        'Rivero moves money between your own accounts when you '
                        'apply. The rest changes ${salaryAcc.name} only when '
                        'you pay it: tap the category on the Plan tab, or the '
                        'bank message is matched.',
                        style: RiveroTypography.bodySmall,
                      ),
                    ),
                  if (short > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: RiveroSpacing.sm),
                      child: Text(
                        '${salaryAcc.name} holds '
                        '${money(salaryAcc.balanceMinorUnits)}; this takes it '
                        '${money(short)} below zero. Has your salary arrived?',
                        key: const ValueKey('moves-warning'),
                        style: RiveroTypography.bodySmall.copyWith(
                          color: RiveroColors.warning,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
                  : () => _apply(salary, split, moves, salaryAcc),
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
    this.destination,
    this.onPickDestination,
  });

  /// Where this category's money arrives ("Paid outside Rivero" if nowhere).
  final String? destination;
  final VoidCallback? onPickDestination;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bucket.name, style: RiveroTypography.bodyLarge),
                  if (destination != null)
                    InkWell(
                      key: ValueKey('dest-${bucket.id}'),
                      borderRadius: RiveroRadii.borderSm,
                      onTap: onPickDestination,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '→ $destination',
                          style: RiveroTypography.bodySmall.copyWith(
                            color: RiveroColors.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
