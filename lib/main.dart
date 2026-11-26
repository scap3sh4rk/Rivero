import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rivero/core/backup/auto_backup.dart';
import 'package:rivero/core/backup/drive_backup.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/ingestion/capture_decisions.dart';
import 'package:rivero/core/ingestion/mandate_tracker.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/reminders/reminder_planner.dart';
import 'package:rivero/core/security/app_lock.dart';
import 'package:rivero/core/security/database_key_manager.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/features/main/data_gate.dart';
import 'package:rivero/features/main/main_screen.dart';
import 'package:rivero/features/settings/screens/about_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();

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

  // A part of a screen that fails to draw shows a calm note, never the
  // error's text (that stays in the log; details only in debug builds).
  ErrorWidget.builder = (details) {
    return Container(
      padding: const EdgeInsets.all(RiveroSpacing.md),
      alignment: Alignment.center,
      color: RiveroColors.surfaceElevated,
      child: Text(
        kDebugMode
            ? 'Unable to render: ${details.exception.toString().split('\n').first}'
            : 'This part could not be shown. Go back and open it again.',
        style: RiveroTypography.bodySmall,
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
    // The home-screen widget follows Safe to spend whenever it changes.
    ref.listenManual(homeWidgetTextProvider, (_, v) {
      if (v != null) NotificationBridge.updateHomeWidget(v.amount, v.caption);
    }, fireImmediately: true);
    Future.microtask(() {
      final sync = ref.read(settingsSyncProvider);
      sync.load().then((_) => sync.listen());
      _drain();
      _maintain();
      if (NotificationBridge.supported) {
        NotificationBridge(ref.read(ingestionServiceProvider))
            .listenForCaptures(afterDrain: _openRequested);
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

  /// Theme, font and look of the last build (see build).
  String? _styleKey;

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
  Future<void> _maintaining = Future.value();

  /// One run at a time: a resume during a slow backup waits for it instead
  /// of starting a second upload.
  Future<void> _maintain() =>
      _maintaining = _maintaining.then((_) => _maintainOnce());

  Future<void> _maintainOnce() async {
    final now = DateTime.now();
    ref.read(todayProvider.notifier).state = now;
    _midnight?.cancel();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), _maintain);
    try {
      final db = ref.read(databaseProvider);
      await MandateTracker(db).rollOverdue(now);
      // Reminders for the next two weeks, armed in Android's alarm service.
      await replanReminders(db, NotificationBridge.scheduleReminders);
      // Automatic encrypted backup, when due (never shows a screen; a
      // failure, such as no network, just waits for the next time).
      try {
        await AutoBackup(db).runIfDue(DriveBackup().uploadSilently);
      } on Object {
        // Try again on the next start or resume.
      }
      await db.ingestionLogsDao.purgeLogsOlderThan(
        now.subtract(const Duration(days: 90)),
      );
    } on Object {
      // Upkeep must never stop the app from opening.
    }
  }

  Future<void> _drain() async {
    if (!NotificationBridge.supported) return;
    await NotificationBridge(ref.read(ingestionServiceProvider)).drain();
    await _openRequested();
    // Capture notifications need permission on Android 13+; ask once
    // capture is on (Android does not ask again after a refusal).
    if (await NotificationBridge.isEnabled()) {
      await NotificationBridge.askNotifyPermission();
    }
  }

  /// "Open Rivero" was tapped on a capture notification: show that payment
  /// in the quick-add sheet (MainScreen opens it).
  Future<void> _openRequested() async {
    // A launcher shortcut or the widget's Log button.
    switch (await NotificationBridge.takeOpenTab()) {
      case 'log':
        ref.read(selectedNavIndexProvider.notifier).state = MainScreen.logIndex;
      case 'scan':
        ref.read(pendingScanProvider.notifier).state = true;
        ref.read(selectedNavIndexProvider.notifier).state = MainScreen.logIndex;
      case 'activity':
        ref.read(selectedNavIndexProvider.notifier).state =
            MainScreen.activityIndex;
    }
    final id = await NotificationBridge.takeOpenRequest();
    if (id == null) return;
    final t = await CaptureDecisions(ref.read(databaseProvider)).entryFor(id);
    if (t == null) return;
    ref.read(selectedNavIndexProvider.notifier).state = 2; // Home
    ref.read(openCaptureProvider.notifier).state = t.id;
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
    final look = ref.watch(lookProvider);
    final light =
        mode == AppThemeMode.light ||
        (mode == AppThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.light);
    // Colours, fonts and sizes are read from tokens, so after a change
    // every widget is rebuilt in place: the open screen stays open (no
    // remount back to Home while trying options in Appearance).
    final styleKey = '$light-$font-${look.toJson()}';
    if (_styleKey != null && _styleKey != styleKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        void rebuild(Element e) {
          e
            ..markNeedsBuild()
            ..visitChildren(rebuild);
        }

        if (mounted) (context as Element).visitChildren(rebuild);
      });
    }
    _styleKey = styleKey;
    return MaterialApp(
      title: 'Rivero',
      debugShowCheckedModeBanner: false,
      theme: RiveroTheme.build(light: light, font: font, look: look),
      // Text size from Appearance, on top of the phone's own setting.
      // App lock wraps the whole navigator, so when it locks it covers every
      // screen, sheet and dialog that was open, not only the first screen.
      // ponytail: locking drops the open screens (unlock starts on Home);
      // keep them mounted under the lock only if users miss their place.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(
              mq.textScaler.scale(1) * look.textScale,
            ),
          ),
          child: AppLockGate(child: child!),
        );
      },
      home: switch (ref.watch(onboardedProvider)) {
        null => Scaffold(backgroundColor: RiveroColors.background),
        _ => const DataGate(child: MainScreen()),
      },
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
