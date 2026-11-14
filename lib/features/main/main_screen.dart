import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/eager_page_physics.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/features/accounts/screens/accounts_screen.dart';
import 'package:rivero/features/home/screens/home_screen.dart';
import 'package:rivero/features/log/quick_log_screen.dart';
import 'package:rivero/features/owed/owed_screen.dart';
import 'package:rivero/features/tour/app_tour.dart';
import 'package:rivero/features/transactions/screens/transactions_screen.dart';

/// App shell: swipeable pages with a Slice-style row of round icon buttons.
/// Tabs: Home, Accounts, Log (keypad), Activity, Plan. Settings lives behind
/// the profile button.
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  // Home sits in the middle so every other page is at most two swipes away.
  static const homeIndex = 2;
  static const logIndex = 3;
  static const activityIndex = 4;

  static const _screens = <Widget>[
    OwedScreen(asTab: true),
    AccountsScreen(),
    HomeScreen(),
    QuickLogScreen(),
    TransactionsScreen(),
  ];

  static const _tabs = <(IconData, IconData, String)>[
    (Icons.handshake_outlined, Icons.handshake_rounded, 'Owed'),
    (Icons.account_balance_outlined, Icons.account_balance_rounded, 'Accounts'),
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.dialpad_rounded, Icons.dialpad_rounded, 'Log'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Activity'),
  ];

  late final int _initial = ref.read(openOnLogProvider) ? logIndex : homeIndex;
  late int _settled = _initial;
  late final PageController _pager = PageController(initialPage: _initial);
  int _dragStart = 0;
  double _dragDx = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(selectedNavIndexProvider.notifier).state = _initial;
      // First run: a guided tour, once Home has appeared.
      if (ref.read(tourPendingProvider)) {
        _tourTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted && ref.read(tourPendingProvider)) AppTour.show(context);
        });
      }
    });
  }

  Timer? _tourTimer;

  @override
  void dispose() {
    _tourTimer?.cancel();
    _pager.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(selectedNavIndexProvider.notifier).state = i;
    _settled = i;
    _pager.animateToPage(
      i,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(selectedNavIndexProvider);
    ref.listen(selectedNavIndexProvider, (_, i) {
      final page = _pager.hasClients ? _pager.page?.round() : null;
      if (page != null && page != i) _goTo(i);
    });
    // Back steps out one level at a time: clear Activity's search/filter,
    // then return to Home, and only then leave the app. Pushed pages and
    // sheets above this screen close normally first.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final index = ref.read(selectedNavIndexProvider);
        final query = ref.read(activityQueryProvider);
        final filter = ref.read(activityFilterProvider);
        final range = ref.read(activityRangeProvider);
        if (index == activityIndex &&
            (query.isNotEmpty ||
                filter != ActivityFilter.all ||
                range != null)) {
          ref.read(activityQueryProvider.notifier).state = '';
          ref.read(activityFilterProvider.notifier).state = ActivityFilter.all;
          ref.read(activityRangeProvider.notifier).state = null;
        } else if (index != homeIndex) {
          _goTo(homeIndex);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: RiveroColors.background,
        body: NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            final page = _pager.page;
            if (page != null) _settled = page.round();
            return false;
          },
          child: PageView(
            controller: _pager,
            pageSnapping: false,
            physics: EagerPagePhysics(settledPage: () => _settled),
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              ref.read(selectedNavIndexProvider.notifier).state = i;
            },
            children: _screens,
          ),
        ),
        bottomNavigationBar: SafeArea(
          // Swiping along the bar scrubs between tabs, one tab per ~56px.
          child: GestureDetector(
            key: const ValueKey('nav-bar'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) {
              _dragStart = ref.read(selectedNavIndexProvider);
              _dragDx = 0;
            },
            onHorizontalDragUpdate: (d) {
              _dragDx += d.delta.dx;
              final target = (_dragStart + (_dragDx / 56).round()).clamp(
                0,
                _tabs.length - 1,
              );
              if (target != ref.read(selectedNavIndexProvider)) {
                HapticFeedback.selectionClick();
                _goTo(target);
              }
            },
            child: SizedBox(
              height: 84,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    _NavButton(
                      key: ValueKey('nav-${_tabs[i].$3}'),
                      icon: _tabs[i].$1,
                      selectedIcon: _tabs[i].$2,
                      label: _tabs[i].$3,
                      selected: i == current,
                      onTap: () => _goTo(i),
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

/// Round icon button; the active one grows and lightens with a springy ease.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 66.0 : 46.0;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
              // Opaque so the button reads clearly over scrolling content.
              color: selected
                  ? Color.alphaBlend(
                      RiveroColors.accent.withValues(alpha: 0.22),
                      RiveroColors.surfaceElevated,
                    )
                  : RiveroColors.surfaceElevated,
            ),
            child: Icon(
              selected ? selectedIcon : icon,
              size: selected ? 28 : 22,
              color: selected
                  ? RiveroColors.accent
                  : RiveroColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
