import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/storage/media_store.dart';

/// Wrong passphrase, or a file that is not a Rivero backup / was altered.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Turns a raw error from Google sign-in or the Drive API into something a
/// person can act on. Unknown errors keep their text, shortened.
String friendlyBackupError(Object error) {
  final t = error.toString();
  final lower = t.toLowerCase();
  if (lower.contains('apiexception: 10') ||
      lower.contains('developer_error') ||
      lower.contains('apiexception: 12500') ||
      lower.contains('clientconfigurationerror') ||
      lower.contains('serverclientid')) {
    return 'Google sign-in is not set up for this version of Rivero yet '
        '(the signing key of this build must be registered with Google). '
        'Back up to a file instead: Save a backup file.';
  }
  if (lower.contains('apiexception: 12501') ||
      lower.contains('canceled') ||
      lower.contains('cancelled')) {
    return 'Sign-in was cancelled.';
  }
  if (lower.contains('apiexception: 7') ||
      lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network')) {
    return 'No internet connection. Try again when you are online, or save a '
        'backup file.';
  }
  if (lower.contains('403') ||
      lower.contains('accessnotconfigured') ||
      lower.contains('drive api has not been used')) {
    return 'Google Drive access is not enabled for Rivero yet. Back up to a '
        'file instead.';
  }
  if (lower.contains('401') || lower.contains('invalid_token')) {
    return 'Google sign-in expired. Sign in again.';
  }
  return 'Something went wrong: ${t.length > 120 ? '${t.substring(0, 120)}…' : t}';
}

/// Backups: every table as JSON, plus bill photos and account pictures,
/// encrypted with a passphrase-derived key (PBKDF2-HMAC-SHA256 ->
/// AES-256-GCM) before it ever leaves the phone.
///
/// Raw bank message text is never included (privacy); entries keep their
/// details. Restoring checks the backup's schema and repairs data from
/// older versions the same way the database migrations do.
class BackupCodec {
  const BackupCodec({this.iterations = 210000});

  /// PBKDF2 rounds; lowered only in tests.
  final int iterations;

  static const _format = 'rivero-backup';
  static const _version = 1;

  // ---- data <-> json -----------------------------------------------------

  static Future<Map<String, dynamic>> export(RiveroDatabase db) async {
    List<Map<String, dynamic>> rows(List<dynamic> list) => [
      for (final r in list) (r as dynamic).toJson() as Map<String, dynamic>,
    ];
    final accounts = rows(await db.select(db.physicalAccounts).get());
    final txns = [
      for (final t in rows(await db.select(db.transactions).get()))
        {...t, 'ingestionLogId': null}, // raw messages are not backed up
    ];
    // Pictures travel inside the backup, keyed by their file name.
    final media = <Map<String, String>>[];
    Future<void> add(String? path, String folder) async {
      if (path == null) return;
      final f = File(path);
      if (!f.existsSync()) return;
      media.add({
        'folder': folder,
        'name': p.basename(path),
        'data': base64Encode(await f.readAsBytes()),
      });
    }

    for (final a in accounts) {
      await add(a['imagePath'] as String?, MediaStore.accountImages);
    }
    for (final t in txns) {
      await add(t['attachmentPath'] as String?, MediaStore.bills);
    }
    return {
      'schema': db.schemaVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'physicalAccounts': accounts,
      'allocationBuckets': rows(await db.select(db.allocationBuckets).get()),
      'transactions': txns,
      'mandates': rows(await db.select(db.mandates).get()),
      'associatedTitles': rows(await db.select(db.associatedTitles).get()),
      'dues': rows(await db.select(db.dues).get()),
      'appSettings': rows(await db.select(db.appSettings).get()),
      'media': media,
    };
  }

  /// Replaces everything in [db] with [data], atomically. Pictures are
  /// written back first and their paths pointed at the new files.
  static Future<void> restore(
    RiveroDatabase db,
    Map<String, dynamic> data,
  ) async {
    final schema = (data['schema'] as int?) ?? 1;
    if (schema > db.schemaVersion) {
      throw const BackupException(
        'This backup was made by a newer Rivero. Update the app first.',
      );
    }
    List<Map<String, dynamic>> list(String k) =>
        ((data[k] as List?) ?? const []).cast<Map<String, dynamic>>();

    final moved = <String, String>{};
    for (final m in list('media')) {
      final path = await MediaStore.write(
        m['folder'] as String,
        m['name'] as String,
        base64Decode(m['data'] as String),
      );
      moved[m['name'] as String] = path;
    }
    String? relink(Object? path) =>
        path == null ? null : moved[p.basename(path as String)];

    await db.transaction(() async {
      await db.wipeAll();
      // Parents before children (foreign keys). Columns added after the
      // backup was made get their defaults.
      for (final j in list('physicalAccounts')) {
        await db
            .into(db.physicalAccounts)
            .insert(
              PhysicalAccount.fromJson({
                'creditLimitMinorUnits': 0,
                'accountType': 'Bank',
                'sortOrder': 0,
                ...j,
                'imagePath': relink(j['imagePath']),
              }),
            );
      }
      for (final j in list('allocationBuckets')) {
        await db
            .into(db.allocationBuckets)
            .insert(
              AllocationBucket.fromJson({'carryOverMinorUnits': 0, ...j}),
            );
      }
      for (final j in list('rawIngestionLogs')) {
        await db.into(db.rawIngestionLogs).insert(RawIngestionLog.fromJson(j));
      }
      for (final j in list('transactions')) {
        await db
            .into(db.transactions)
            .insert(
              LedgerTransaction.fromJson({
                ...j,
                'attachmentPath': relink(j['attachmentPath']),
              }),
            );
      }
      for (final j in list('mandates')) {
        await db.into(db.mandates).insert(Mandate.fromJson(j));
      }
      for (final j in list('associatedTitles')) {
        await db.into(db.associatedTitles).insert(AssociatedTitle.fromJson(j));
      }
      for (final j in list('dues')) {
        await db.into(db.dues).insert(Due.fromJson(j));
      }
      for (final j in list('appSettings')) {
        await db.into(db.appSettings).insert(AppSetting.fromJson(j));
      }
      // The same repairs the database migrations make (see database.dart).
      if (schema < 8) {
        await db.customStatement(
          'UPDATE allocation_buckets SET carry_over_minor_units = 0',
        );
      }
      if (schema < 9) {
        await db.customStatement(
          'UPDATE allocation_buckets SET linked_physical_account_id = NULL '
          "WHERE role != 'expense'",
        );
      }
    });
  }

  // ---- encryption ----------------------------------------------------------

  Future<SecretKey> _key(String passphrase, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  Future<List<int>> encrypt(
    Map<String, dynamic> data,
    String passphrase,
  ) async {
    if (passphrase.length < 8) {
      throw const BackupException('Use a passphrase of at least 8 characters');
    }
    final aes = AesGcm.with256bits();
    final salt = SecretKeyData.random(length: 16).bytes;
    final box = await aes.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: await _key(passphrase, salt),
    );
    return utf8.encode(
      jsonEncode({
        'format': _format,
        'v': _version,
        'kdf': 'pbkdf2-sha256',
        'iter': iterations,
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'data': base64Encode(box.cipherText),
      }),
    );
  }

  Future<Map<String, dynamic>> decrypt(
    List<int> file,
    String passphrase,
  ) async {
    Map<String, dynamic> head;
    try {
      head = jsonDecode(utf8.decode(file)) as Map<String, dynamic>;
    } on Object {
      throw const BackupException('This is not a Rivero backup file');
    }
    if (head['format'] != _format) {
      throw const BackupException('This is not a Rivero backup file');
    }
    final salt = base64Decode(head['salt'] as String);
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: head['iter'] as int,
      bits: 256,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64Decode(head['data'] as String),
          nonce: base64Decode(head['nonce'] as String),
          mac: Mac(base64Decode(head['mac'] as String)),
        ),
        secretKey: key,
      );
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } on SecretBoxAuthenticationError {
      throw const BackupException('Wrong passphrase, or the file was changed');
    }
  }
}
