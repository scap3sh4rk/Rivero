import 'dart:ffi';

import 'package:sqlite3/open.dart';

/// Prepares the environment for running Drift in-memory tests on Linux/macOS.
void setupTestDatabase() {
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so.0');
    } on Object catch (_) {
      return DynamicLibrary.open('/usr/lib/x86_64-linux-gnu/libsqlite3.so.0');
    }
  });
}
