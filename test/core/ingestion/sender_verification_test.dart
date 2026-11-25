import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/plan/defaults.dart';

import '../../test_helper.dart';

/// "Accept automatically" only trusts a sender Rivero can verify: anyone
/// can send an SMS worded like a bank's.
void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  setUp(() async {
    db = RiveroDatabase.memory();
    final at = DateTime(2026, 11, 25);
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('sbi'),
        name: const Value('SBI Savings'),
        institution: const Value('SBI'),
        accountMask: const Value('4012'),
        balanceMinorUnits: const Value(1500000),
        createdAt: Value(at),
        updatedAt: Value(at),
      ),
    );
    await ensureDefaults(db);
    await db.settingsDao.set(SettingKeys.captureAutoAccept, '1');
  });
  tearDown(() => db.close());

  const body =
      'Rs 45,000.00 credited to A/c XX4012 from VPA refund@ybl '
      '(UPI Ref No 431712345678). -SBI';

  Future<(TransactionState, int)> capture(String? pkg, String sender) async {
    final r = await IngestionService(database: db).processNotification(
      RawNotification(
        id: '$pkg:$sender',
        packageName: pkg,
        sender: sender,
        title: sender,
        body: body,
        receivedAt: DateTime(2026, 11, 25, 10),
      ),
    );
    final t = await db.transactionsDao.getTransactionById(
      r.persistedTransactionId!,
    );
    final bal = (await db.accountsDao.getPhysicalAccountById('sbi'))!
        .balanceMinorUnits;
    return (t!.transactionState, bal);
  }

  test('an SMS from a phone number waits for the user', () async {
    final (state, bal) = await capture(
      'com.google.android.apps.messaging',
      '+919812345678',
    );
    expect(state, TransactionState.needsReview);
    expect(bal, 1500000);
  });

  test("another app titling itself like a bank's SMS waits too", () async {
    final (state, bal) = await capture('com.example.anyapp', 'VM-SBIINB');
    expect(state, TransactionState.needsReview);
    expect(bal, 1500000);
  });

  test(
    "a bank's SMS (DLT header in an SMS app) still counts by itself",
    () async {
      final (state, bal) = await capture(
        'com.google.android.apps.messaging',
        'VM-SBIINB',
      );
      expect(state, TransactionState.confirmed);
      expect(bal, 1500000 + 4500000);
    },
  );
}
