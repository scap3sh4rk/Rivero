import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

const _encryptedName = 'rivero_encrypted.db';
const _legacyPlainName = 'rivero_unencrypted.db';

String _sqlQuote(String s) => s.replaceAll("'", "''");

/// Opens the app database encrypted with [key] (SQLite3MultipleCiphers).
///
/// * Fails loudly if the SQLite build has no cipher support, rather than
///   silently writing plaintext.
/// * A pre-encryption `rivero_unencrypted.db` is migrated once, then deleted.
/// * [directory] exists for tests; production uses the app documents folder.
QueryExecutor openEncryptedConnection(String key, {Directory? directory}) {
  return LazyDatabase(() async {
    final dir = directory ?? await getApplicationDocumentsDirectory();
    final encrypted = File(p.join(dir.path, _encryptedName));
    final legacy = File(p.join(dir.path, _legacyPlainName));
    return NativeDatabase.createInBackground(
      encrypted,
      isolateSetup: () => _migrateLegacy(legacy, encrypted, key),
      setup: (raw) {
        if (raw.select('PRAGMA cipher;').isEmpty) {
          throw StateError(
            'SQLite has no encryption support; refusing to open',
          );
        }
        raw.execute("PRAGMA key = '${_sqlQuote(key)}';");
      },
    );
  });
}

/// Encrypts an old plaintext database: copy (VACUUM INTO), rekey the copy,
/// move it into place, delete the plaintext original.
void _migrateLegacy(File legacy, File encrypted, String key) {
  if (!legacy.existsSync() || encrypted.existsSync()) return;
  final tmp = File('${encrypted.path}.tmp');
  if (tmp.existsSync()) tmp.deleteSync();

  final plain = sqlite3.open(legacy.path);
  try {
    plain.execute("VACUUM INTO '${_sqlQuote(tmp.path)}'");
  } finally {
    plain.dispose();
  }
  final copy = sqlite3.open(tmp.path);
  try {
    copy.execute("PRAGMA rekey = '${_sqlQuote(key)}';");
  } finally {
    copy.dispose();
  }
  tmp.renameSync(encrypted.path);
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('${legacy.path}$suffix');
    if (f.existsSync()) f.deleteSync();
  }
}
