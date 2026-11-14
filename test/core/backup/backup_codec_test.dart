import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/backup/backup_codec.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/dues/dues_service.dart';

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
}
