import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  late IngestionService service;
  final now = DateTime(2026, 11, 14, 10);

  Future<void> feed(String id, String body, {int offsetSeconds = 0}) =>
      service.processNotification(
        RawNotification(
          id: id,
          body: body,
          receivedAt: now.add(Duration(seconds: offsetSeconds)),
          sender: 'VK-HDFCBK',
        ),
      );

  Future<void> account(String id, String mask) =>
      db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: Value(id),
          name: Value(id),
          institution: const Value('Bank'),
          accountMask: Value(mask),
          balanceMinorUnits: const Value(5000000),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

  setUp(() async {
    db = RiveroDatabase.memory();
    service = IngestionService(database: db);
    await account('salary', '4012');
    await account('spend', '8841');
    await db.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: const Value('b'),
        name: const Value('Expenses'),
        role: const Value(AccountRole.expense),
        allocatedMinorUnits: const Value(7000000),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> spent() async =>
      (await db.accountsDao.getBucketById('b'))!.spentMinorUnits;
  Future<int> bal(String id) async =>
      (await db.accountsDao.getPhysicalAccountById(id))!.balanceMinorUnits;

  test(
    'salary -> spending account transfer is neither expense nor income',
    () async {
      await feed(
        'd',
        'HDFC Bank: Rs 20,000.00 debited from a/c **4012 on 13-11-26 transferred to a/c XX8841 UPI Ref No 431712345678.',
      );
      expect(
        await spent(),
        2000000,
      ); // looks like an expense until its partner arrives

      await feed(
        'c',
        'ICICI Bank: Rs 20,000.00 credited to a/c XX8841 on 13-11-26 by UPI Ref No 431712345678.',
        offsetSeconds: 20,
      );

      final txns = await db.select(db.transactions).get();
      expect(txns, hasLength(2));
      expect(
        txns.every(
          (t) => t.transactionType == TransactionType.internalTransfer,
        ),
        isTrue,
      );
      expect(txns.every((t) => t.isInternalTransfer), isTrue);
      expect(await spent(), 0); // budget handed back
      expect(await bal('salary'), 5000000 - 2000000);
      expect(await bal('spend'), 5000000 + 2000000);
    },
  );

  test('a genuine expense with no partner is untouched', () async {
    await feed(
      'e',
      'HDFC Bank: Rs 500.00 debited from a/c **4012 on 13-11-26 to VPA swiggy@hdfcbank (UPI Ref No 431712345679).',
    );
    await feed(
      'x',
      'ICICI Bank: Rs 999.00 credited to a/c XX8841 on 13-11-26 by UPI Ref No 431712345680.',
      offsetSeconds: 20,
    );
    expect(await spent(), 50000);
  });

  test('the balance in a bank message is never taken: only the amount moves '
      'it', () async {
    final before = await bal('salary');
    await feed(
      'e',
      'HDFC Bank: Rs 500.00 debited from a/c **4012 on 13-11-26 to VPA swiggy@hdfcbank (UPI Ref No 431712345679). Avl bal: Rs 12,345.67',
    );
    expect(await bal('salary'), before - 50000);
  });
}
