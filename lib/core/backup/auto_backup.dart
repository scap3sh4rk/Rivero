import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rivero/core/backup/backup_codec.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';

/// How often automatic backups run.
enum BackupFrequency { off, daily, weekly }

/// Encrypted backups that run by themselves (on app start and resume, when
/// due) to the user's Google Drive, with the passphrase kept in the phone's
/// keystore (never in plain text, never uploaded).
class AutoBackup {
  AutoBackup(
    this.db, {
    FlutterSecureStorage? secureStorage,
    this.codec = const BackupCodec(),
  }) : _secure = secureStorage ?? const FlutterSecureStorage();

  final RiveroDatabase db;
  final BackupCodec codec;
  final FlutterSecureStorage _secure;

  static const _passKey = 'rivero_auto_backup_passphrase_v1';

  /// Remind the user when nothing has been backed up for this long.
  static const staleAfter = Duration(days: 14);

  Future<BackupFrequency> frequency() async {
    final v = await db.settingsDao.get(SettingKeys.autoBackup);
    return BackupFrequency.values.where((f) => f.name == v).firstOrNull ??
        BackupFrequency.off;
  }

  Future<DateTime?> lastBackup() async {
    final v = await db.settingsDao.get(SettingKeys.lastBackupAt);
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Call after any successful backup (manual or automatic).
  Future<void> markBackedUp(DateTime at) =>
      db.settingsDao.set(SettingKeys.lastBackupAt, at.toIso8601String());

  /// Turns automatic backups on (with [passphrase] stored in the keystore)
  /// or off (the stored passphrase is erased).
  Future<void> configure(BackupFrequency f, {String? passphrase}) async {
    if (f == BackupFrequency.off) {
      await _secure.delete(key: _passKey);
    } else {
      if (passphrase == null || passphrase.length < 8) {
        throw const BackupException(
          'Use a passphrase of at least 8 characters',
        );
      }
      await _secure.write(key: _passKey, value: passphrase);
    }
    await db.settingsDao.set(SettingKeys.autoBackup, f.name);
  }

  /// Whether a backup is due at [now].
  static bool isDue(BackupFrequency f, DateTime? last, DateTime now) {
    if (f == BackupFrequency.off) return false;
    if (last == null) return true;
    final every = f == BackupFrequency.daily
        ? const Duration(days: 1)
        : const Duration(days: 7);
    return !now.difference(last).isNegative && now.difference(last) >= every;
  }

  /// Backs up if due. [upload] sends the encrypted bytes and returns false
  /// when it could not (for example, Drive needs signing in again). Returns
  /// true when a backup was made.
  Future<bool> runIfDue(
    Future<bool> Function(List<int> bytes) upload, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final f = await frequency();
    if (!isDue(f, await lastBackup(), at)) return false;
    final pass = await _secure.read(key: _passKey);
    if (pass == null) return false;
    final bytes = await codec.encrypt(await BackupCodec.export(db), pass);
    if (!await upload(bytes)) return false;
    await markBackedUp(at);
    return true;
  }
}
