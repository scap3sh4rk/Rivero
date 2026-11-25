import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/capture_decisions.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/plan/defaults.dart';

import '../../test_helper.dart';

/// What was chosen in a capture notification's popup is applied once the
/// capture has been processed.
void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  final at = DateTime(2026, 11, 14, 10);
  const body =
      'Rs 450.00 debited from A/c XX4012 to VPA swiggy@hdfcbank '
      '(UPI Ref No 431712345678). Avl bal: Rs 45,000.00';

  setUp(() async {
    db = RiveroDatabase.memory();
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('bank'),
        name: const Value('bank'),
        institution: const Value('Bank'),
        accountMask: const Value('4012'),
        balanceMinorUnits: const Value(5000000),
        createdAt: Value(at),
        updatedAt: Value(at),
      ),
    );
    await ensureDefaults(db); // review-first
  });
  tearDown(() => db.close());

  Future<void> capture(String id) => IngestionService(database: db)
      .processNotification(
        RawNotification(
          id: id,
          sender: 'VM-HDFCBK',
          body: body,
          receivedAt: at,
        ),
      );
  Future<int> bal() async =>
      (await db.accountsDao.getPhysicalAccountById('bank'))!.balanceMinorUnits;

  test('Add with a category and note: confirmed, counted, labelled', () async {
    await capture('pkg:key:1');
    await CaptureDecisions(db).apply({
      'pkg:key:1': {'action': 'accept', 'category': 'Food', 'note': 'Lunch'},
    });
    final t = (await CaptureDecisions(db).entryFor('pkg:key:1'))!;
    expect(t.transactionState, TransactionState.confirmed);
    expect(t.category, 'Food');
    expect(t.userNotes, 'Lunch');
    expect(await bal(), 4955000); // only the amount, never the "Avl bal"
  });

  test('Ignore: nothing is counted', () async {
    await capture('pkg:key:2');
    await CaptureDecisions(db).apply({
      'pkg:key:2': {'action': 'ignore', 'category': null, 'note': null},
    });
    final t = (await CaptureDecisions(db).entryFor('pkg:key:2'))!;
    expect(t.transactionState, TransactionState.ignored);
    expect(await bal(), 5000000);
  });

  test('Add with another account picked: the payment moves there', () async {
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('other'),
        name: const Value('other'),
        institution: const Value('Other'),
        accountMask: const Value('9999'),
        balanceMinorUnits: const Value(1000000),
        createdAt: Value(at),
        updatedAt: Value(at),
      ),
    );
    await capture('pkg:key:4');
    await CaptureDecisions(db).apply({
      'pkg:key:4': {
        'action': 'accept',
        'category': 'Food',
        'note': null,
        'account': 'other',
      },
    });
    final t = (await CaptureDecisions(db).entryFor('pkg:key:4'))!;
    expect(t.physicalAccountId, 'other');
    expect(t.transactionState, TransactionState.confirmed);
    expect(await bal(), 5000000); // the account the message named is untouched
    final other = await db.accountsDao.getPhysicalAccountById('other');
    expect(other!.balanceMinorUnits, 1000000 - 45000);
  });

  test('a decision for a capture that made no entry is skipped', () async {
    final n = await CaptureDecisions(db).apply({
      'nothing:here': {'action': 'accept', 'category': 'Food', 'note': null},
    });
    expect(n, 0);
  });
}
