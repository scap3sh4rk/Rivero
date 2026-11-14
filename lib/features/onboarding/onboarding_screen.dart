import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/plan/onboarding.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// First-run setup in three short steps: pay day + salary, accounts, split.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pager = PageController();
  int _step = 0;
  bool _saving = false;

  int _day = 1;
  bool _separate = false;
  final _salary = TextEditingController();
  final _salaryName = TextEditingController();
  final _salaryMask = TextEditingController();
  final _salaryBalance = TextEditingController();
  final _expName = TextEditingController();
  final _expMask = TextEditingController();
  final _expBalance = TextEditingController();
  final _invest = TextEditingController();
  final _savings = TextEditingController();

  @override
  void dispose() {
    _pager.dispose();
    for (final c in [
      _salary,
      _salaryName,
      _salaryMask,
      _salaryBalance,
      _expName,
      _expMask,
      _expBalance,
      _invest,
      _savings,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _salaryMinor => parseAmountMinorUnits(_salary.text);
  int get _split =>
      parseAmountMinorUnits(_invest.text) +
      parseAmountMinorUnits(_savings.text);

  bool get _stepValid => switch (_step) {
    0 => _salaryMinor > 0,
    1 =>
      _salaryName.text.trim().isNotEmpty &&
          (!_separate || _expName.text.trim().isNotEmpty),
    _ => _split <= _salaryMinor,
  };

  Future<void> _next() async {
    if (_step < 2) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _step++);
      await _pager.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    setState(() => _saving = true);
    await completeOnboarding(
      ref.read(databaseProvider),
      OnboardingData(
        salaryDay: _day,
        salaryMinor: _salaryMinor,
        salaryAccountName: _salaryName.text,
        salaryInstitution: _salaryName.text,
        salaryMask: _salaryMask.text,
        salaryBalanceMinor: parseAmountMinorUnits(_salaryBalance.text),
        expenseName: _separate ? _expName.text : null,
        expenseInstitution: _expName.text,
        expenseMask: _expMask.text,
        expenseBalanceMinor: parseAmountMinorUnits(_expBalance.text),
        investMinor: parseAmountMinorUnits(_invest.text),
        savingsMinor: parseAmountMinorUnits(_savings.text),
      ),
    );
    ref.read(userSalaryDayProvider.notifier).state = _day;
    ref.read(monthlySalaryProvider.notifier).state = _salaryMinor;
    ref.read(onboardedProvider.notifier).state = true;
  }

  Widget _page(
    String title,
    String subtitle,
    List<Widget> children, {
    bool logo = false,
  }) => ListView(
    padding: const EdgeInsets.all(RiveroSpacing.xl),
    children: [
      if (logo) ...[
        Image.asset('assets/icon/logo.png', width: 72, height: 72),
        const SizedBox(height: RiveroSpacing.lg),
      ],
      Text(title, style: RiveroTypography.displayLarge.copyWith(fontSize: 30)),
      const SizedBox(height: RiveroSpacing.sm),
      Text(subtitle, style: RiveroTypography.bodyMedium),
      const SizedBox(height: RiveroSpacing.xxl),
      ...children,
    ],
  );

  Widget _field(
    TextEditingController c,
    String label, {
    bool money = false,
    bool digits = false,
    int? maxLength,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: RiveroSpacing.md),
    child: TextField(
      key: key,
      controller: c,
      maxLength: maxLength,
      keyboardType: money
          ? const TextInputType.numberWithOptions(decimal: true)
          : digits
          ? TextInputType.number
          : TextInputType.text,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        prefixText: money ? '₹' : null,
        counterText: '',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RiveroColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(RiveroSpacing.xl),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 4,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: i <= _step
                              ? RiveroColors.textPrimary
                              : RiveroColors.surfaceInteractive,
                          borderRadius: RiveroRadii.borderFull,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pager,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _page(
                    'When do you get paid?',
                    'Your cycle runs from pay day to pay day.',
                    [
                      _field(
                        _salary,
                        'Monthly salary',
                        money: true,
                        key: const ValueKey('ob-salary'),
                      ),
                      Text(
                        'Pay day of month: $_day',
                        style: RiveroTypography.titleMedium,
                      ),
                      Slider(
                        value: _day.toDouble(),
                        min: 1,
                        max: 31,
                        divisions: 30,
                        label: '$_day',
                        onChanged: (v) => setState(() => _day = v.round()),
                      ),
                    ],
                    logo: true,
                  ),
                  _page(
                    'Where does it land?',
                    'Add your salary account. You can add more later.',
                    [
                      _field(
                        _salaryName,
                        'Salary account (e.g. HDFC Salary)',
                        key: const ValueKey('ob-name'),
                      ),
                      _field(
                        _salaryMask,
                        'Last 4 digits (helps match notifications)',
                        digits: true,
                        maxLength: 4,
                      ),
                      _field(_salaryBalance, 'Current balance', money: true),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('I spend from a different account'),
                        value: _separate,
                        onChanged: (v) => setState(() => _separate = v),
                      ),
                      if (_separate) ...[
                        _field(
                          _expName,
                          'Spending account (e.g. ICICI Spends)',
                        ),
                        _field(
                          _expMask,
                          'Last 4 digits',
                          digits: true,
                          maxLength: 4,
                        ),
                        _field(_expBalance, 'Current balance', money: true),
                      ],
                    ],
                  ),
                  _page(
                    'How do you split it?',
                    'Whatever you leave empty is skipped. Everything else goes to spending.',
                    [
                      _field(_invest, 'Investments per month', money: true),
                      _field(_savings, 'Savings per month', money: true),
                      if (_split > _salaryMinor)
                        Text(
                          'This is more than your salary.',
                          style: RiveroTypography.bodySmall.copyWith(
                            color: RiveroColors.danger,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(RiveroSpacing.xl),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: _stepValid && !_saving ? _next : null,
                  child: Text(_step < 2 ? 'Continue' : 'Start'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
