import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/ingestion/mandate_tracker.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/security/app_lock.dart';
import 'package:rivero/core/security/database_key_manager.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/features/main/main_screen.dart';
import 'package:rivero/features/onboarding/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final RiveroDatabase db;
  try {
    final key = await DatabaseKeyManager().getOrCreateMasterKey();
    db = RiveroDatabase.encrypted(key);
    // The connection is lazy: touch it now so a failure shows here, not as
    // a blank screen later.
    await db.customSelect('SELECT 1').get();
  } on Object catch (e) {
    runApp(StartupErrorApp(error: '$e'));
    return;
  }

  // Gracefully handle UI errors without displaying harsh full-screen red boxes
  ErrorWidget.builder = (details) {
    return Container(
      padding: const EdgeInsets.all(RiveroSpacing.md),
      alignment: Alignment.center,
      color: RiveroColors.surfaceElevated,
      child: Text(
        'Unable to render: ${details.exception.toString().split('\n').first}',
        style: RiveroTypography.bodySmall.copyWith(
          color: RiveroColors.expenseAccent,
          fontSize: 11,
        ),
        textAlign: TextAlign.center,
      ),
    );
  };

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const RiveroApp(),
    ),
  );
}

/// Root widget of the Rivero application.
class RiveroApp extends ConsumerStatefulWidget {
  const RiveroApp({super.key});

  @override
  ConsumerState<RiveroApp> createState() => _RiveroAppState();
}

class _RiveroAppState extends ConsumerState<RiveroApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      final sync = ref.read(settingsSyncProvider);
      sync.load().then((_) => sync.listen());
      _drain();
      _maintain();
      if (NotificationBridge.supported) {
        NotificationBridge(ref.read(ingestionServiceProvider))
            .listenForCaptures();
      }
      _loadTheme();
    });
  }

  // ponytail: one-word text file instead of a prefs package; swap if more prefs appear.
  Future<File> _themeFile() async => File(
    p.join((await getApplicationDocumentsDirectory()).path, 'theme_mode.txt'),
  );

  Future<void> _loadTheme() async {
    try {
      final name = await (await _themeFile()).readAsString();
      ref.read(themeModeProvider.notifier).state = AppThemeMode.values
          .firstWhere((m) => m.name == name.trim());
    } on Object {
      // first launch or unreadable: keep dark default
    }
  }

  Future<void> _saveTheme(AppThemeMode mode) async {
    try {
      await (await _themeFile()).writeAsString(mode.name);
    } on Object {
      // non-fatal: theme just won't persist
    }
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  Timer? _midnight;

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _drain();
      _maintain();
    }
  }

  /// Daily upkeep, on start, on resume and at midnight: today's date (so
  /// days-to-payday is never stale), autopays whose date passed unseen,
  /// and raw bank messages older than 90 days (privacy).
  Future<void> _maintain() async {
    final now = DateTime.now();
    ref.read(todayProvider.notifier).state = now;
    _midnight?.cancel();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), _maintain);
    try {
      final db = ref.read(databaseProvider);
      await MandateTracker(db).rollOverdue(now);
      await db.ingestionLogsDao.purgeLogsOlderThan(
        now.subtract(const Duration(days: 90)),
      );
    } on Object {
      // Upkeep must never stop the app from opening.
    }
  }

  void _drain() {
    if (!NotificationBridge.supported) return;
    NotificationBridge(ref.read(ingestionServiceProvider)).drain();
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..listen(themeModeProvider, (_, mode) => _saveTheme(mode))
      ..listen(
        appLockEnabledProvider,
        (_, on) => NotificationBridge.setSecure(on: on),
      );
    final mode = ref.watch(themeModeProvider);
    final font = ref.watch(fontFamilyProvider);
    final light =
        mode == AppThemeMode.light ||
        (mode == AppThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.light);
    // Colours are read statically, so remount the tree when the mode flips.
    return KeyedSubtree(
      key: ValueKey('$light-$font'),
      child: MaterialApp(
        title: 'Rivero',
        debugShowCheckedModeBanner: false,
        theme: RiveroTheme.build(light: light, font: font),
        home: switch (ref.watch(onboardedProvider)) {
          null => Scaffold(backgroundColor: RiveroColors.background),
          true => const AppLockGate(child: MainScreen()),
          false => const OnboardingScreen(),
        },
      ),
    );
  }
}

/// Shown instead of a blank screen when the encrypted data cannot be opened
/// (for example after the phone's keystore was reset). Nothing is deleted.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: RiveroTheme.build(light: false),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(RiveroSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rivero could not open your data',
                  style: RiveroTypography.titleLarge,
                ),
                const SizedBox(height: RiveroSpacing.md),
                Text(
                  'Your data is stored encrypted on this phone and has not '
                  'been changed. Close the app and try again. If this keeps '
                  "happening, the phone's secure key may have been reset: "
                  'reinstall and restore from your backup.',
                  style: RiveroTypography.bodyMedium,
                ),
                const SizedBox(height: RiveroSpacing.lg),
                Text(error, style: RiveroTypography.bodySmall, maxLines: 4),
                const SizedBox(height: RiveroSpacing.xl),
                const FilledButton(
                  onPressed: SystemNavigator.pop,
                  child: Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
