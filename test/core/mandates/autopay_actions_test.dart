import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/mandate_tracker.dart';
import 'package:rivero/core/mandates/autopay_actions.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  final now = DateTime(2026, 11, 16, 10);
  final due = DateTime(2026, 11, 5);

  Future<void> account(int balance) => db.accountsDao.upsertPhysicalAccount(
    PhysicalAccountsCompanion(
      id: const Value('bank'),
      name: const Value('HDFC'),
      institution: const Value('HDFC'),
      accountMask: const Value('1234'),
      balanceMinorUnits: Value(balance),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );

  Future<Mandate> sip() async {
    await db.mandatesDao.upsertMandate(
      MandatesCompanion(
        id: const Value('sip'),
        payee: const Value('Axis Bluechip SIP'),
        amountMinorUnits: const Value(500000),
        frequency: const Value(MandateFrequency.monthly),
        physicalAccountId: const Value('bank'),
        startDate: Value(now),
        nextExecutionDate: Value(due),
        status: const Value(MandateStatus.active),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return (await db.mandatesDao.getMandateById('sip'))!;
  }

  setUp(() => db = RiveroDatabase.memory());
  tearDown(() => db.close());

  test('kinds are guessed from the name until the user picks one', () async {
    await account(1000000);
    final m = await sip();
    expect(m.kind, MandateKind.other);
    expect(AutopayActions.kindOf(m), MandateKind.sip);
    expect(MandateKind.guess('Netflix'), MandateKind.subscription);
    expect(MandateKind.guess('HDFC Home Loan EMI'), MandateKind.emi);
    expect(MandateKind.guess('LIC premium'), MandateKind.insurance);
    expect(MandateKind.guess('BESCOM electricity'), MandateKind.utility);
    expect(
      AutopayActions.kindOf(m.copyWith(kind: MandateKind.rent)),
      MandateKind.rent,
    );
  });

  test('an overdue autopay on a short account is not assumed paid', () async {
    await account(100000); // ₹1,000 < ₹5,000 SIP
    await sip();
    await MandateTracker(db).rollOverdue(now); // 11 days overdue
    final m = (await db.mandatesDao.getMandateById('sip'))!;
    expect(m.nextExecutionDate, due); // still overdue
    // ...and still kept aside in Safe to spend.
    expect(upcomingMandates([m], now, DateTime(2026, 11, 30)), [m]);
  });

  test('with enough money it is assumed paid after the grace days', () async {
    await account(1000000);
    await sip();
    await MandateTracker(db).rollOverdue(now);
    final m = (await db.mandatesDao.getMandateById('sip'))!;
    expect(m.nextExecutionDate, DateTime(2026, 12, 5));
  });

  test('"It was paid" records an investment on the due date, once', () async {
    await account(1000000);
    final m = await sip();
    await AutopayActions(db).markPaid(m);
    final t = (await db.select(db.transactions).get()).single;
    expect(t.amountMinorUnits, -500000);
    expect(t.transactionType, TransactionType.investmentContribution);
    expect(t.transactionTimestamp, due);
    final after = (await db.mandatesDao.getMandateById('sip'))!;
    expect(after.nextExecutionDate, DateTime(2026, 12, 5));
  });

  test(
    '"It failed" keeps it aside until the retry date; skip moves on',
    () async {
      await account(100000);
      final m = await sip();
      await AutopayActions(db).retryOn(m, DateTime(2026, 11, 20, 15));
      var after = (await db.mandatesDao.getMandateById('sip'))!;
      expect(after.nextExecutionDate, DateTime(2026, 11, 20));
      await AutopayActions(db).skip(after);
      after = (await db.mandatesDao.getMandateById('sip'))!;
      expect(after.nextExecutionDate, DateTime(2026, 12, 20));
      expect(await db.select(db.transactions).get(), isEmpty);
    },
  );
}
