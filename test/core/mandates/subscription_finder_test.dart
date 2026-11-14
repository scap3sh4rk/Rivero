import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/mandates/subscription_finder.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  final now = DateTime(2026, 11, 14);
  var n = 0;

  Future<void> pay(String merchant, int minor, DateTime at) =>
      db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: Value('t${n++}'),
          physicalAccountId: const Value('bank'),
          amountMinorUnits: Value(-minor),
          transactionType: const Value(TransactionType.expense),
          transactionState: const Value(TransactionState.confirmed),
          merchant: Value(merchant),
          category: const Value('Fun'),
          transactionTimestamp: Value(at),
          createdAt: Value(at),
        ),
      );

  setUp(() async {
    db = RiveroDatabase.memory();
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('bank'),
        name: const Value('bank'),
        institution: const Value('Bank'),
        accountMask: const Value('4012'),
        balanceMinorUnits: const Value(5000000),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    // Netflix on the 5th, three months running: a subscription.
    for (final m in [8, 9, 10]) {
      await pay('Netflix', 64900, DateTime(2026, m, 5));
    }
    // Swiggy three times but at random intervals and amounts: not one.
    await pay('Swiggy', 45000, DateTime(2026, 10, 2));
    await pay('Swiggy', 12000, DateTime(2026, 10, 9));
    await pay('Swiggy', 30000, DateTime(2026, 11, 2));
    // Gym weekly, but only twice: not enough to call it.
    await pay('Gym', 50000, DateTime(2026, 11, 2));
    await pay('Gym', 50000, DateTime(2026, 11, 9));
  });
  tearDown(() => db.close());

  test('finds the monthly subscription only, with its next date', () async {
    final s = await SubscriptionFinder(db).find(now: now);
    expect(s.map((x) => x.merchant), ['Netflix']);
    expect(s.single.amountMinorUnits, 64900);
    expect(s.single.frequency, MandateFrequency.monthly);
    expect(s.single.next, DateTime(2026, 12, 5));
  });

  test('accepting adds an autopay; it is not suggested again', () async {
    final f = SubscriptionFinder(db);
    await f.accept((await f.find(now: now)).single);
    final m = await db.select(db.mandates).getSingle();
    expect(m.payee, 'Netflix');
    expect(m.status, MandateStatus.active);
    expect(await f.find(now: now), isEmpty);
  });

  test('"Not autopay" hides it for good', () async {
    final f = SubscriptionFinder(db);
    await f.dismiss((await f.find(now: now)).single);
    expect(await f.find(now: now), isEmpty);
  });
}
