import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/goals/goals.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  final start = DateTime(2026, 7, 2);
  final now = DateTime(2026, 11, 2); // 4 months in

  setUp(() async {
    db = RiveroDatabase.memory();
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('rd'),
        name: const Value('Trip RD'),
        institution: const Value('Bank'),
        accountMask: const Value('9999'),
        balanceMinorUnits: const Value(1000000), // ₹10,000
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: const Value('trip'),
        name: const Value('Trip'),
        role: const Value(AccountRole.savings),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  });
  tearDown(() => db.close());

  test('linked account: saved is its balance; behind and per month', () async {
    // ₹60,000 from 2 Jul 2026 to 2 Jul 2027.
    final g = Goal(
      id: 'g',
      name: 'Goa',
      targetMinorUnits: 6000000,
      start: start,
      by: DateTime(2027, 7, 2),
      accountId: 'rd',
    );
    final p = await Goals(db).progress(g, now: now);
    expect(p.savedMinorUnits, 1000000);
    // ₹50,000 left over 8 months = ₹6,250 a month.
    expect(p.perMonthMinorUnits, 625000);
    // A third of the way (123 of 365 days): about ₹20,219 expected.
    expect(p.behindByMinorUnits, 6000000 * 123 ~/ 365 - 1000000);
    expect(p.reached, isFalse);
  });

  test('plan category: counts payments into it since the start', () async {
    Future<void> pay(String id, int minor, DateTime at) =>
        db.transactionsDao.insertTransaction(
          TransactionsCompanion(
            id: Value(id),
            physicalAccountId: const Value('rd'),
            allocationBucketId: const Value('trip'),
            amountMinorUnits: Value(minor),
            transactionType: const Value(TransactionType.planTransfer),
            transactionState: const Value(TransactionState.confirmed),
            merchant: const Value('Plan: Trip'),
            category: const Value('Trip'),
            transactionTimestamp: Value(at),
            createdAt: Value(at),
          ),
        );
    await pay('old', -500000, DateTime(2026, 6, 2)); // before the goal
    await pay('a', -500000, DateTime(2026, 8, 2));
    await pay('a-in', 500000, DateTime(2026, 8, 2)); // the other leg
    await pay('b', -700000, DateTime(2026, 9, 2));
    final g = Goal(
      id: 'g',
      name: 'Trip',
      targetMinorUnits: 1000000,
      start: start,
      by: DateTime(2027, 1, 2),
      bucketId: 'trip',
    );
    final p = await Goals(db).progress(g, now: now);
    expect(p.savedMinorUnits, 1200000);
    expect(p.reached, isTrue);
    expect(p.perMonthMinorUnits, 0);
    expect(p.behindByMinorUnits, 0);
  });

  test('goals round-trip through settings', () async {
    final g = Goal(
      id: 'g',
      name: 'Bike',
      targetMinorUnits: 9000000,
      start: start,
      by: DateTime(2027, 3, 2),
    );
    await Goals(db).save([g]);
    final back = (await Goals(db).load()).single;
    expect(back.name, 'Bike');
    expect(back.by, DateTime(2027, 3, 2));
    expect(back.accountId, isNull);
  });
}
