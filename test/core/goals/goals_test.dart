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
      sources: const [GoalSource.account('rd')],
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
      sources: const [GoalSource.bucket('trip')],
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
    expect(back.sources, isEmpty);
  });

  test(
    'several sources add up: an FD with its interest, cash, an account',
    () async {
      final today = DateTime(2026, 11, 2);
      await db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: const Value('fd'),
          name: const Value('SBI FD'),
          institution: const Value('SBI'),
          accountMask: const Value('1111'),
          accountType: const Value('Fixed Deposit'),
          balanceMinorUnits: const Value(10000000), // ₹1,00,000 in
          fdRateBps: const Value(700),
          fdStartDate: Value(DateTime(2026, 8, 2)), // one quarter ago
          fdMaturityDate: Value(DateTime(2027, 8, 2)),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      final g = Goal(
        id: 'car',
        name: 'Car',
        targetMinorUnits: 50000000,
        start: start,
        by: DateTime(2027, 7, 2),
        sources: const [
          GoalSource.account('fd'),
          GoalSource.account('rd'),
          GoalSource.asset('Cash at home', 2000000),
        ],
      );
      final p = await Goals(db).progress(g, now: today);
      // FD with one quarter of interest (₹1,750), the RD's ₹10,000, ₹20,000.
      expect(p.parts.map((x) => x.value), [10175000, 1000000, 2000000]);
      expect(p.savedMinorUnits, 13175000);
      expect(p.parts.first.name, 'SBI FD');
    },
  );

  test('goals saved before sources existed still load', () async {
    final g = Goal.fromJson({
      'id': 'old',
      'name': 'Trip',
      'target': 100,
      'by': '2027-01-02T00:00:00.000',
      'start': '2026-07-02T00:00:00.000',
      'account': 'rd',
    });
    expect(g.sources.single.kind, GoalSourceKind.account);
    expect(g.sources.single.id, 'rd');
  });

  test('put adds or replaces; remove deletes', () async {
    final g = Goal(
      id: 'g',
      name: 'Bike',
      targetMinorUnits: 100,
      start: start,
      by: DateTime(2027, 3, 2),
    );
    final goals = Goals(db);
    await goals.put(g);
    await goals.put(g.copyWith(name: 'Scooter'));
    expect((await goals.load()).single.name, 'Scooter');
    await goals.remove('g');
    expect(await goals.load(), isEmpty);
  });
}
