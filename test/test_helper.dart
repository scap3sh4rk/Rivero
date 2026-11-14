import 'package:rivero/design_system/widgets/launch_splash.dart';

/// Shared test setup. SQLite (with SQLite3MultipleCiphers) comes from the
/// sqlite3 build hook, so no library override is needed; the launch intro is
/// switched off so tests see the app straight away.
void setupTestDatabase() {
  LaunchOverlay.enabled = false;
}
