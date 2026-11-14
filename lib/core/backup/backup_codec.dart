import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:rivero/core/database/database.dart';

/// Wrong passphrase, or a file that is not a Rivero backup / was altered.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Backups: every table as JSON, encrypted with a passphrase-derived key
/// (PBKDF2-HMAC-SHA256 -> AES-256-GCM) before it ever leaves the phone.
///
/// Photos are not included (only their paths); restoring keeps entries but
/// pictures from another phone will be missing.
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
    return {
      'schema': db.schemaVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'physicalAccounts': rows(await db.select(db.physicalAccounts).get()),
      'allocationBuckets': rows(await db.select(db.allocationBuckets).get()),
      'rawIngestionLogs': rows(await db.select(db.rawIngestionLogs).get()),
      'transactions': rows(await db.select(db.transactions).get()),
      'mandates': rows(await db.select(db.mandates).get()),
      'associatedTitles': rows(await db.select(db.associatedTitles).get()),
      'dues': rows(await db.select(db.dues).get()),
      'appSettings': rows(await db.select(db.appSettings).get()),
    };
  }

  /// Replaces everything in [db] with [data], atomically.
  static Future<void> restore(RiveroDatabase db, Map<String, dynamic> data) {
    List<Map<String, dynamic>> list(String k) =>
        ((data[k] as List?) ?? const []).cast<Map<String, dynamic>>();
    return db.transaction(() async {
      await db.wipeAll();
      // Parents before children (foreign keys).
      for (final j in list('physicalAccounts')) {
        await db.into(db.physicalAccounts).insert(PhysicalAccount.fromJson(j));
      }
      for (final j in list('allocationBuckets')) {
        await db
            .into(db.allocationBuckets)
            .insert(AllocationBucket.fromJson(j));
      }
      for (final j in list('rawIngestionLogs')) {
        await db.into(db.rawIngestionLogs).insert(RawIngestionLog.fromJson(j));
      }
      for (final j in list('transactions')) {
        await db.into(db.transactions).insert(LedgerTransaction.fromJson(j));
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
