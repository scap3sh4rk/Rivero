import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/engine/allocation_rule.dart';
import 'package:rivero/core/engine/waterfall_allocator.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ingestion/parser/message_intent.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/core/ledger/ledger_service.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  late LedgerService ledger;
  final now = DateTime(2026, 11, 14);

  setUp(() async {
    db = RiveroDatabase.memory();
    ledger = LedgerService(db);
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('bank'),
        name: const Value('Bank'),
        institution: const Value('Bank'),
        accountMask: const Value('4012'),
        balanceMinorUnits: const Value(100000), // ₹1,000
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: const Value('b'),
        name: const Value('Spending'),
        role: const Value(AccountRole.expense),
        allocatedMinorUnits: const Value(100000),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> spent() async =>
      (await db.accountsDao.getBucketById('b'))!.spentMinorUnits;
  Future<int> balance() async =>
      (await db.accountsDao.getPhysicalAccountById('bank'))!.balanceMinorUnits;

  test(
    'spending more than the account holds goes negative, and undoes cleanly',
    () async {
      final id = await ledger.recordManual(
        accountId: 'bank',
        amountMinorUnits: -250000, // ₹2,500 from a ₹1,000 account
        type: TransactionType.expense,
        merchant: 'Big spend',
        category: 'Shopping',
      );
      expect(await balance(), -150000);
      expect(await spent(), 250000); // budget overspent, not wrapped or clamped
      await ledger.remove(id);
      expect(await balance(), 100000);
      expect(await spent(), 0);
    },
  );

  test(
    "a refund larger than this cycle's spend gives budget back, no wrap",
    () async {
      await ledger.recordManual(
        accountId: 'bank',
        amountMinorUnits: 30000,
        type: TransactionType.refund,
        merchant: 'Refund from last month',
        category: 'Shopping',
      );
      expect(await spent(), -30000); // extra budget; documented behaviour
      expect(await balance(), 130000);
    },
  );

  test('confirming twice and deleting twice never double-apply', () async {
    final id = await ledger.recordManual(
      accountId: 'bank',
      amountMinorUnits: -20000,
      type: TransactionType.expense,
      merchant: 'x',
      category: 'Other',
    );
    await ledger.confirm(id); // already confirmed: no-op
    expect(await spent(), 20000);
    await ledger.remove(id);
    await ledger.remove(id); // already gone: no-op
    expect(await balance(), 100000);
    expect(await spent(), 0);
  });

  test('one bad notification does not lose the ones behind it', () async {
    final bridge = NotificationBridge(IngestionService(database: db));
    final good = {
      'id': 'ok-1',
      'package': 'com.phonepe.app',
      'title': 'PhonePe',
      'body': 'Rs 250.00 debited from A/c XX4012 to Chai Stall',
      'time': 1700000000000,
    };
    final broken = {'id': 'bad', 'package': 'x', 'body': null, 'time': 'later'};
    final count = await bridge.ingestJson(jsonEncode([broken, good]));
    expect(count, 1);
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('an absurdly long number in a bank message is ignored, not a crash', () async {
    final service = IngestionService(database: db);
    final huge = '9' * 40;
    // Neither of these may throw.
    await service.processNotification(
      RawNotification(
        id: 'h1',
        body: 'Rs $huge debited from A/c XX4012 on 13-11-26',
        receivedAt: now,
        sender: 'VK-HDFCBK',
      ),
    );
    await service.processNotification(
      RawNotification(
        id: 'h2',
        body:
            'Rs $huge will be debited from A/c XX4012 on 16-Nov-26 towards Netflix',
        receivedAt: now,
        sender: 'VK-HDFCBK',
      ),
    );
    expect(await balance(), 100000); // nothing was applied
  });

  test('impossible dates in messages are not silently shifted', () {
    expect(extractNoticeDate('debited on 31-Feb-26'), isNull);
    expect(extractNoticeDate('on 31/04/2026'), isNull);
    expect(extractNoticeDate('on 29/02/2028'), DateTime(2028, 2, 29)); // leap
    expect(extractNoticeDate('on 29/02/2027'), isNull);
  });

  test('percentage allocation uses whole-number maths on large salaries', () {
    const allocator = WaterfallAllocator();
    final r = allocator.allocate(
      salaryReceived: 99999999999, // near the supported maximum
      rules: const [
        AllocationRule(
          id: 'r',
          bucketId: 'a',
          type: AllocationType.percentageOfSalary,
          percentage: 12.5,
        ),
      ],
    );
    expect(r.allocations['a'], (99999999999 * 1250 + 5000) ~/ 10000);
    expect(r.allocations['a']! + r.unallocatedRemaining, 99999999999);
  });
}
