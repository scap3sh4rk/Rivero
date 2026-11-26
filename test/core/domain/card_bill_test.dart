import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/card_cycle.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/reminders/reminder_planner.dart';

import '../../test_helper.dart';

/// Statement on the 21st, payment due on the 5th: the bill generated on
/// 21 Nov is due on 5 Dec; what is spent from 21 Nov goes on the bill of
/// 21 Dec (due 5 Jan).
void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  setUp(() async {
    db = RiveroDatabase.memory();
    final at = DateTime(2026, 11);
    Future<void> acc(String id, int bal, {bool card = false}) =>
        db.accountsDao.upsertPhysicalAccount(
          PhysicalAccountsCompanion(
            id: Value(id),
            name: Value(id),
            institution: const Value('Bank'),
            accountMask: Value(card ? '9999' : '1111'),
            balanceMinorUnits: Value(bal),
            isLiability: Value(card),
            creditLimitMinorUnits: Value(card ? 10000000 : 0),
            statementDay: Value(card ? 21 : null),
            paymentDueDay: Value(card ? 5 : null),
            createdAt: Value(at),
            updatedAt: Value(at),
          ),
        );
    await acc('bank', 5000000);
    // Owes ₹10,000 in all.
    await acc('card', -1000000, card: true);
    var n = 0;
    Future<void> spend(
      DateTime when,
      int rupees, {
      TransactionType type = TransactionType.creditCardPurchase,
      TransactionState state = TransactionState.confirmed,
    }) => db.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: Value('t${n++}'),
        physicalAccountId: const Value('card'),
        amountMinorUnits: Value(-rupees * 100),
        transactionType: Value(type),
        transactionState: Value(state),
        merchant: const Value('Shop'),
        category: const Value('Food'),
        transactionTimestamp: Value(when),
        createdAt: Value(when),
      ),
    );
    await spend(DateTime(2026, 11, 20, 18), 2000); // on the 21 Nov bill
    await spend(DateTime(2026, 11, 21, 10), 3000); // statement day: next bill
    await spend(DateTime(2026, 11, 25, 12), 1000); // next bill
    // Neither counts: a balance update and one still waiting for Accept.
    await spend(
      DateTime(2026, 11, 22),
      500,
      type: TransactionType.balanceAdjustment,
    );
    await spend(
      DateTime(2026, 11, 23),
      700,
      state: TransactionState.needsReview,
    );
  });
  tearDown(() => db.close());

  Future<CardBill> billOn(DateTime now) async => CardBill.of(
    accounts: await db.accountsDao.getAllActivePhysicalAccounts(),
    transactions: await db.select(db.transactions).get(),
    now: now,
  )['card']!;

  test('the cycle starts on the statement day; the bill is due on the 5th', () {
    final c = CardCycle.of(
      statementDay: 21,
      paymentDueDay: 5,
      now: DateTime(2026, 11, 26),
    )!;
    expect(c.cycleStart, DateTime(2026, 11, 21));
    expect(c.nextStatement, DateTime(2026, 12, 21));
    expect(c.dueDate, DateTime(2026, 12, 5));
    expect(c.lastDue, DateTime(2026, 12, 5));
  });

  test('the bill leaves out what was spent from the statement day', () async {
    final b = await billOn(DateTime(2026, 11, 26));
    expect(b.due, 600000); // ₹10,000 − ₹4,000 spent since 21 Nov
    expect(b.nextBill, 400000);
    expect(b.overdueSince, isNull);
  });

  test('a reminder every day from 5 days before the due date', () async {
    final plan = await replanReminders(
      db,
      (_) async {},
      now: DateTime(2026, 11, 28, 20),
    );
    final card = plan.where((r) => r.id.startsWith('card-')).toList();
    expect(card.map((r) => r.at), [
      for (final d in [30, 1, 2, 3, 4, 5])
        DateTime(2026, d == 30 ? 11 : 12, d, 9),
    ]);
    expect(card.first.title, 'card bill ₹6,000.00 due in 5 days');
    expect(card[4].title, 'card bill ₹6,000.00 due tomorrow');
    expect(card.last.title, 'card bill ₹6,000.00 due today');
    expect(card.last.body, startsWith('Pay by 5 Dec.'));
  });

  test('unpaid after the 5th: overdue, a reminder every day', () async {
    final b = await billOn(DateTime(2026, 12, 7));
    expect(b.due, 600000);
    expect(b.overdueSince, DateTime(2026, 12, 5));
    final plan = await replanReminders(
      db,
      (_) async {},
      now: DateTime(2026, 12, 7, 20),
    );
    final card = plan.where((r) => r.id.startsWith('card-')).toList();
    expect(card.first.at, DateTime(2026, 12, 8, 9));
    expect(card.length, 13); // every day for the next two weeks
    expect(card.first.title, 'card bill ₹6,000.00 is overdue');
    // Never moved to next month's deadline.
    expect(card.any((r) => r.title.contains('due in')), isFalse);
  });

  test(
    'paid by the 5th: nothing due, no reminders until the next bill',
    () async {
      // The ₹6,000 bill was paid: only the ₹4,000 of the new cycle is owed.
      await (db.update(
        db.physicalAccounts,
      )..where((a) => a.id.equals('card'))).write(
        const PhysicalAccountsCompanion(balanceMinorUnits: Value(-400000)),
      );
      final b = await billOn(DateTime(2026, 12, 7));
      expect(b.due, 0);
      expect(b.nextBill, 400000);
      expect(b.overdueSince, isNull);
      final plan = await replanReminders(
        db,
        (_) async {},
        now: DateTime(2026, 12, 7, 20),
      );
      expect(plan.where((r) => r.id.startsWith('card-')), isEmpty);
    },
  );
}
