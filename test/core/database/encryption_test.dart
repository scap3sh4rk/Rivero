import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('rivero_enc_'));
  tearDown(() => dir.deleteSync(recursive: true));

  bool isPlainSqlite(File f) =>
      String.fromCharCodes(f.readAsBytesSync().take(15)) == 'SQLite format 3';

  test(
    'database file is encrypted and reopens with the same key only',
    () async {
      var db = RiveroDatabase.encrypted('k3y-one', directory: dir);
      await db.settingsDao.set('secret', 'salary-8000000');
      await db.close();

      final file = File('${dir.path}/rivero_encrypted.db');
      expect(file.existsSync(), isTrue);
      expect(isPlainSqlite(file), isFalse);
      expect(
        String.fromCharCodes(file.readAsBytesSync()).contains('salary-8000000'),
        isFalse,
      );

      db = RiveroDatabase.encrypted('k3y-one', directory: dir);
      expect(await db.settingsDao.get('secret'), 'salary-8000000');
      await db.close();

      final wrong = RiveroDatabase.encrypted('another-key', directory: dir);
      await expectLater(wrong.settingsDao.get('secret'), throwsA(anything));
      await wrong.close().catchError((_) {});
    },
  );

  test(
    'a legacy plaintext database is migrated, encrypted and removed',
    () async {
      final plainFile = File('${dir.path}/rivero_unencrypted.db');
      final legacy = RiveroDatabase(NativeDatabase(plainFile));
      await legacy.settingsDao.set(SettingKeys.salaryDay, '25');
      await legacy.close();
      expect(isPlainSqlite(plainFile), isTrue);

      final db = RiveroDatabase.encrypted("it's-a-key", directory: dir);
      expect(await db.settingsDao.getInt(SettingKeys.salaryDay), 25);
      await db.close();

      expect(plainFile.existsSync(), isFalse);
      expect(isPlainSqlite(File('${dir.path}/rivero_encrypted.db')), isFalse);
    },
  );
}
