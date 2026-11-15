import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/brand_wordmark.dart';

class _Step {
  const _Step(this.tab, this.icon, this.title, this.text);
  final int tab;
  final IconData icon;
  final String title;
  final String text;
}

/// First-run tour: a card over the real app that walks through each tab
/// (switching it behind the card) so every part is understood before use.
/// Shown once; replayable from Settings.
class AppTour extends ConsumerStatefulWidget {
  const AppTour({super.key});

  static const homeTab = 2;
  static const accountsTab = 1;

  static const _steps = <_Step>[
    _Step(
      homeTab,
      Icons.home_rounded,
      'Welcome to Rivero',
      '$riveroTagline.\n\nThis is Home. The big number is how much you can '
          'safely spend per day until payday. Tap it any time to see exactly '
          'how it is worked out.',
    ),
    _Step(
      accountsTab,
      Icons.account_balance_rounded,
      'Start here: your accounts',
      'Add every bank account, wallet, cash and credit card you use with the '
          '+ button. Cards also take their statement and due dates, so Rivero '
          'can show the days left and whether you can pay. The eye icon hides '
          'or shows all balances.',
    ),
    _Step(
      homeTab,
      Icons.pie_chart_outline_rounded,
      'Then: your salary plan',
      'On Home, open PLAN. Enter your salary and split it: what you spend, '
          'invest, save, and what goes to rent or family. Applying it moves '
          'money between your own accounts, and never below zero.',
    ),
    _Step(
      3,
      Icons.dialpad_rounded,
      'Log a payment in two taps',
      'Type the amount, pick a category, add a description if you like, '
          'and Save. Use it for cash, or anything Rivero did not capture.',
    ),
    _Step(
      4,
      Icons.receipt_long_rounded,
      'Activity: everything that happened',
      'Search, filter, attach a bill photo, split a bill or fix an entry. '
          'Captured payments you should check wait for one tap on Home.',
    ),
    _Step(
      0,
      Icons.handshake_rounded,
      'Owed: money in both directions',
      'Track what friends owe you, what you owe others, and everything you '
          'have to pay: autopays, credit card bills and loans, all in one '
          'place.',
    ),
    _Step(
      homeTab,
      Icons.notifications_active_outlined,
      'Let Rivero capture payments',
      'Tap the profile button, then Capture. Allow notification access, and '
          'choose the UPI app you use most so its payment notifications are '
          'recognised. Rivero never asks for SMS permission.',
    ),
  ];

  /// Shows the tour above the current screen.
  static Future<void> show(BuildContext context) => showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, _, _) => const AppTour(),
    transitionBuilder: (_, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  );

  @override
  ConsumerState<AppTour> createState() => _AppTourState();
}

class _AppTourState extends ConsumerState<AppTour> {
  int _i = 0;

  Future<void> _finish({required bool toAccounts}) async {
    await ref.read(databaseProvider).settingsDao.set(SettingKeys.tourDone, '1');
    ref.read(tourPendingProvider.notifier).state = false;
    if (toAccounts) {
      ref.read(selectedNavIndexProvider.notifier).state = AppTour.accountsTab;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _go(int i) {
    setState(() => _i = i);
    ref.read(selectedNavIndexProvider.notifier).state = AppTour._steps[i].tab;
  }

  @override
  Widget build(BuildContext context) {
    final step = AppTour._steps[_i];
    final last = _i == AppTour._steps.length - 1;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          // Above the bottom row of tab buttons.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RiveroSpacing.lg,
              0,
              RiveroSpacing.lg,
              96,
            ),
            child: Container(
              key: const ValueKey('tour-card'),
              padding: const EdgeInsets.all(RiveroSpacing.xl),
              decoration: BoxDecoration(
                color: RiveroColors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: RiveroColors.borderMedium),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: RiveroColors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(step.icon, color: RiveroColors.accent),
                      ),
                      const SizedBox(width: RiveroSpacing.md),
                      Expanded(
                        child: Text(
                          step.title,
                          style: RiveroTypography.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RiveroSpacing.md),
                  Text(step.text, style: RiveroTypography.bodyMedium),
                  const SizedBox(height: RiveroSpacing.lg),
                  Row(
                    children: [
                      for (var d = 0; d < AppTour._steps.length; d++)
                        Container(
                          width: d == _i ? 18 : 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: d == _i
                                ? RiveroColors.accent
                                : RiveroColors.surfaceInteractive,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      const Spacer(),
                      if (_i > 0)
                        TextButton(
                          key: const ValueKey('tour-back'),
                          onPressed: () => _go(_i - 1),
                          child: const Text('Back'),
                        )
                      else
                        TextButton(
                          key: const ValueKey('tour-skip'),
                          onPressed: () => _finish(toAccounts: false),
                          child: const Text('Skip'),
                        ),
                      const SizedBox(width: RiveroSpacing.xs),
                      FilledButton(
                        key: const ValueKey('tour-next'),
                        onPressed: () =>
                            last ? _finish(toAccounts: true) : _go(_i + 1),
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        child: Text(last ? 'Add my accounts' : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
