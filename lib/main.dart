import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/features/main/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const ProviderScope(child: RiveroApp()));
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
      ref.read(databaseSeederProvider).seedIfEmpty();
      _drain();
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _drain();
  }

  void _drain() {
    if (!NotificationBridge.supported) return;
    NotificationBridge(ref.read(ingestionServiceProvider)).drain();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(themeModeProvider, (_, mode) => _saveTheme(mode));
    final mode = ref.watch(themeModeProvider);
    final light =
        mode == AppThemeMode.light ||
        (mode == AppThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.light);
    // Colours are read statically, so remount the tree when the mode flips.
    return KeyedSubtree(
      key: ValueKey(light),
      child: MaterialApp(
        title: 'Rivero',
        debugShowCheckedModeBanner: false,
        theme: RiveroTheme.build(light: light),
        home: const MainScreen(),
      ),
    );
  }
}
