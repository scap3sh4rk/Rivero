import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/backup/auto_backup.dart';
import 'package:rivero/core/backup/backup_codec.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);
  TestWidgetsFlutterBinding.ensureInitialized();

  test('due: off never; first time always; daily and weekly intervals', () {
    final now = DateTime(2026, 11, 14, 10);
    expect(AutoBackup.isDue(BackupFrequency.off, null, now), isFalse);
    expect(AutoBackup.isDue(BackupFrequency.weekly, null, now), isTrue);
    expect(
      AutoBackup.isDue(
        BackupFrequency.daily,
        now.subtract(const Duration(hours: 23)),
        now,
      ),
      isFalse,
    );
    expect(
      AutoBackup.isDue(
        BackupFrequency.daily,
        now.subtract(const Duration(hours: 25)),
        now,
      ),
      isTrue,
    );
    expect(
      AutoBackup.isDue(
        BackupFrequency.weekly,
        now.subtract(const Duration(days: 6)),
        now,
      ),
      isFalse,
    );
  });

  test('runs when due with the stored passphrase, then waits', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();
    final auto = AutoBackup(db, codec: const BackupCodec(iterations: 1000));
    await auto.configure(BackupFrequency.daily, passphrase: 'correct horse');

    final uploads = <List<int>>[];
    Future<bool> upload(List<int> b) async {
      uploads.add(b);
      return true;
    }

    final now = DateTime(2026, 11, 14, 10);
    expect(await auto.runIfDue(upload, now: now), isTrue);
    expect(await auto.lastBackup(), now);
    // The upload is the encrypted backup, and it opens with the passphrase.
    final data = await const BackupCodec(iterations: 1000)
        .decrypt(uploads.single, 'correct horse');
    expect(data['physicalAccounts'], isNotEmpty);
    // Not again the same day.
    expect(
      await auto.runIfDue(upload, now: now.add(const Duration(hours: 3))),
      isFalse,
    );
    // Drive needs signing in again: nothing is marked as backed up.
    expect(
      await auto.runIfDue(
        (_) async => false,
        now: now.add(const Duration(days: 2)),
      ),
      isFalse,
    );
    expect(await auto.lastBackup(), now);
  });

  test('turning it off forgets the passphrase', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    final auto = AutoBackup(db);
    await auto.configure(BackupFrequency.weekly, passphrase: 'longenough');
    await auto.configure(BackupFrequency.off);
    expect(await auto.frequency(), BackupFrequency.off);
    expect(await auto.runIfDue((_) async => true), isFalse);
    await expectLater(
      auto.configure(BackupFrequency.daily, passphrase: 'short'),
      throwsA(isA<BackupException>()),
    );
  });
}
