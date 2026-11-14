import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/backup/backup_codec.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/storage/media_store.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);
  const codec = BackupCodec(iterations: 1000); // fast for tests

  test('encrypted backup restores everything onto a fresh phone', () async {
    final source = RiveroDatabase.memory();
    addTearDown(source.close);
    await DatabaseSeeder(source).seedIfEmpty();
    await DuesService(source).lend(person: 'Ravi', amountMinorUnits: 50000);
    final file = await codec.encrypt(
      await BackupCodec.export(source),
      'correct horse battery',
    );
    expect(String.fromCharCodes(file), isNot(contains('Ravi'))); // encrypted

    final target = RiveroDatabase.memory();
    addTearDown(target.close);
    await BackupCodec.restore(
      target,
      await codec.decrypt(file, 'correct horse battery'),
    );
    expect(
      (await target.accountsDao.getAllActivePhysicalAccounts()).length,
      (await source.accountsDao.getAllActivePhysicalAccounts()).length,
    );
    expect(
      (await target.select(target.transactions).get()).length,
      (await source.select(source.transactions).get()).length,
    );
    expect((await target.select(target.dues).get()).single.person, 'Ravi');
    expect(await target.settingsDao.get(SettingKeys.onboarded), '1');
  });

  test(
    'wrong passphrase or garbage is refused without touching data',
    () async {
      final db = RiveroDatabase.memory();
      addTearDown(db.close);
      await DatabaseSeeder(db).seedIfEmpty();
      final file = await codec.encrypt(
        await BackupCodec.export(db),
        'right passphrase',
      );
      expect(
        () => codec.decrypt(file, 'wrong passphrase'),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => codec.decrypt('hello'.codeUnits, 'x'),
        throwsA(isA<BackupException>()),
      );
      expect(() => codec.encrypt({}, 'short'), throwsA(isA<BackupException>()));
    },
  );

  test('M17/L4/L7: schema checked, old data repaired, photos travel, no raw '
      'messages', () async {
    final tmp = await Directory.systemTemp.createTemp('rivero-media');
    addTearDown(() => tmp.delete(recursive: true));
    MediaStore.rootOverride = tmp;
    addTearDown(() => MediaStore.rootOverride = null);

    final source = RiveroDatabase.memory();
    addTearDown(source.close);
    await DatabaseSeeder(source).seedIfEmpty();
    final photo = File('${tmp.path}/bill.jpg')..writeAsBytesSync([1, 2, 3]);
    final t = (await source.select(source.transactions).get()).first;
    await source.transactionsDao.updateAttachment(t.id, photo.path);
    await source.ingestionLogsDao.insertLog(
      RawIngestionLogsCompanion.insert(
        id: 'raw',
        sourceChannel: IngestionChannel.notificationAndroid,
        rawPayload: 'secret bank text',
        receivedAt: DateTime(2026),
        parseStatus: ParseStatus.parsed,
        createdAt: DateTime(2026),
        confidenceScore: const Value(1),
      ),
    );
    final data = await BackupCodec.export(source);
    expect(jsonEncode(data), isNot(contains('secret bank text')));

    // A newer app's backup is refused, untouched.
    final target = RiveroDatabase.memory();
    addTearDown(target.close);
    await expectLater(
      BackupCodec.restore(target, {...data, 'schema': 999}),
      throwsA(isA<BackupException>()),
    );

    photo.deleteSync(); // "another phone"
    await BackupCodec.restore(target, data);
    final restored = (await target.transactionsDao.getTransactionById(t.id))!;
    expect(File(restored.attachmentPath!).readAsBytesSync(), [1, 2, 3]);

    // A backup from schema 8 gets the v9 repair (set-aside links cleared).
    final old = RiveroDatabase.memory();
    addTearDown(old.close);
    await BackupCodec.restore(old, {...data, 'schema': 8});
    final links = (await old.accountsDao.getAllBuckets())
        .where((b) => b.role != AccountRole.expense)
        .map((b) => b.linkedPhysicalAccountId);
    expect(links.every((l) => l == null), isTrue);
  });

  test('Google errors are explained, not shown raw', () {
    expect(
      friendlyBackupError(
        'PlatformException(sign_in_failed, ApiException: 10, null)',
      ),
      contains('not set up'),
    );
    expect(friendlyBackupError('ApiException: 12501'), contains('cancelled'));
    expect(
      friendlyBackupError('SocketException: Failed host lookup'),
      contains('internet'),
    );
    expect(
      friendlyBackupError('DetailedApiRequestError(status: 403)'),
      contains('not enabled'),
    );
    expect(friendlyBackupError('weird'), startsWith('Something went wrong'));
  });
}
