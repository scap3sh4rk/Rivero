import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/brand_wordmark.dart';
import 'package:rivero/features/budgets/screens/budgets_screen.dart';
import 'package:rivero/features/goals/goals_screen.dart';
import 'package:rivero/features/mandates/mandates_screen.dart';

/// A page the tour opens on top of the tabs to show it.
enum _Page { plan, goals, autopay }

class _Step {
  const _Step(
    this.tab,
    this.icon,
    this.title,
    this.text, {
    this.pages = const [],
  });
  final int tab;
  final IconData icon;
  final String title;
  final String text;

  /// Pages opened (in this order) for this step; none = just the tab.
  final List<_Page> pages;
}

/// First-run tour: a card over the real app that walks through each tab,
/// and opens the Plan, Goals and Autopay pages behind it, so every part is
/// seen before use. Shown once; replayable from Settings.
class AppTour extends ConsumerStatefulWidget {
  const AppTour({required this.navigator, required this.onClose, super.key});

  /// Opens and closes the pages the tour shows.
  final NavigatorState navigator;

  /// Takes the tour off the screen.
  final VoidCallback onClose;

  static const owedTab = 0;
  static const accountsTab = 1;
  static const homeTab = 2;
  static const logTab = 3;
  static const activityTab = 4;

  static const _steps = <_Step>[
    _Step(
      homeTab,
      Icons.home_rounded,
      'Welcome to Rivero',
      '$riveroTagline.\n\nThis is Home. The big number is how much you can '
          'safely spend per day until payday; the card fills like a battery '
          'with what is left. Tap it any time to see how it is worked out.',
    ),
    _Step(
      accountsTab,
      Icons.account_balance_rounded,
      'Start here: your accounts',
      'Add every bank account, wallet, cash, card, loan, investment and fixed '
          'deposit with the + button. They sit in sections you can fold and '
          'reorder. Each has its own eye; the one at the top hides everything.',
    ),
    _Step(
      homeTab,
      Icons.pie_chart_outline_rounded,
      'Then: your salary plan',
      'This is Plan (open it from the PLAN card on Home). Enter your salary '
          'and split it: what you spend, invest, save, and what goes to rent '
          'or family. Applying it moves money between your own accounts, '
          'never below zero.',
      pages: [_Page.plan],
    ),
    _Step(
      homeTab,
      Icons.flag_outlined,
      'Goals',
      'At the bottom of Plan (and on Home): save towards a trip or a car. '
          'Count FDs, accounts, demat, cash, stocks or gold towards it and see '
          'if you are on track.',
      pages: [_Page.plan, _Page.goals],
    ),
    _Step(
      logTab,
      Icons.dialpad_rounded,
      'Log a payment in two taps',
      'Type the amount, pick a category, add a description if you like, '
          'and Save. Use it for cash, or anything Rivero did not capture.',
    ),
    _Step(
      activityTab,
      Icons.receipt_long_rounded,
      'Activity: everything that happened',
      'Search, filter by date or #tag, attach a bill photo, split a bill or '
          'fix an entry. Captured payments to check wait on Home.',
    ),
    _Step(
      owedTab,
      Icons.handshake_rounded,
      'Owed: money in both directions',
      'What friends owe you, what you owe others, and every bill to pay: '
          'each card with its due date and whether its account can pay it.',
    ),
    _Step(
      owedTab,
      Icons.autorenew_rounded,
      'Autopay lives on Owed',
      'Open it from the Autopay row on the Owed tab. SIPs, subscriptions, '
          'EMIs and bills, each marked by kind and editable. Safe to spend '
          'keeps what is due aside; an overdue one asks what happened.',
      pages: [_Page.autopay],
    ),
    _Step(
      homeTab,
      Icons.notifications_active_outlined,
      'Let Rivero capture payments',
      'Tap the profile button, then Settings > Capture. Allow notification '
          'access and choose the UPI app you use most. Rivero never asks for '
          'SMS permission. Settings > Appearance & Home picks the cards on '
          'Home and your bank icons.',
    ),
  ];

  /// Shows the tour above everything, also above the pages it opens.
  /// Works from any context, also the Navigator's own (Settings closes
  /// itself and starts the tour from there).
  static void show(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlay = navigator.overlay!;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => AppTour(navigator: navigator, onClose: entry.remove),
    );
    overlay.insert(entry);
  }

  @override
  ConsumerState<AppTour> createState() => _AppTourState();
}

class _AppTourState extends ConsumerState<AppTour> {
  int _i = 0;

  @override
  void initState() {
    super.initState();
    // Start on the first step's tab (Home), wherever the tour was opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _go(0);
    });
  }

  /// The pages the tour has opened, bottom first.
  final List<_Page> _open = [];

  Widget _pageOf(_Page p) => switch (p) {
    _Page.plan => const BudgetsScreen(),
    _Page.goals => const GoalsScreen(),
    _Page.autopay => const MandatesScreen(),
  };

  /// Opens exactly [want] (closing what is not part of it).
  void _show(List<_Page> want) {
    var keep = 0;
    while (keep < _open.length &&
        keep < want.length &&
        _open[keep] == want[keep]) {
      keep++;
    }
    while (_open.length > keep) {
      widget.navigator.pop();
      _open.removeLast();
    }
    for (final p in want.skip(keep)) {
      widget.navigator.push(
        MaterialPageRoute<void>(builder: (_) => _pageOf(p)),
      );
      _open.add(p);
    }
  }

  Future<void> _finish({required bool toAccounts}) async {
    _show(const []);
    await ref.read(databaseProvider).settingsDao.set(SettingKeys.tourDone, '1');
    ref.read(tourPendingProvider.notifier).state = false;
    if (toAccounts) {
      ref.read(selectedNavIndexProvider.notifier).state = AppTour.accountsTab;
    }
    widget.onClose();
  }

  void _go(int i) {
    setState(() => _i = i);
    final step = AppTour._steps[i];
    ref.read(selectedNavIndexProvider.notifier).state = step.tab;
    _show(step.pages);
  }

  @override
  Widget build(BuildContext context) {
    final step = AppTour._steps[_i];
    final last = _i == AppTour._steps.length - 1;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dims the app and keeps taps on the card while the tour runs.
          const Positioned.fill(
            child: ModalBarrier(color: Color(0x99000000), dismissible: false),
          ),
          SafeArea(
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
                              color: RiveroColors.accent.withValues(
                                alpha: 0.16,
                              ),
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
        ],
      ),
    );
  }
}
