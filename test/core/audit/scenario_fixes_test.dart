import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/engine/sts_breakdown.dart';
import 'package:rivero/core/ingestion/capture_decisions.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/core/ingestion/trai_dlt_validator.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/plan/defaults.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/reconciliation/reconciliation_service.dart';

import '../../test_helper.dart';

/// Journeys from the 15 Nov 2026 scenario audit (H1-H7): each one showed a
/// wrong balance or a wrong Safe to spend before its fix.
void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  late IngestionService capture;
  late LedgerService ledger;
  late SalaryPlanService plan;
  final now = DateTime.now();
  var n = 0;

  Future<void> account(
    String id,
    int balance, {
    String mask = '••••',
    bool card = false,
    String type = 'Savings',
  }) => db.accountsDao.upsertPhysicalAccount(
    PhysicalAccountsCompanion(
      id: Value(id),
      name: Value(id),
      institution: Value(id),
      accountMask: Value(mask),
      balanceMinorUnits: Value(balance),
      isLiability: Value(card),
      accountType: Value(type),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );

  Future<int> bal(String id) async =>
      (await db.accountsDao.getPhysicalAccountById(id))!.balanceMinorUnits;

  Future<String?> sms(
    String body, {
    Duration ago = Duration.zero,
    String sender = 'VM-HDFCBK',
    String? pkg,
    String? title,
    String? id,
  }) async {
    final r = await capture.processNotification(
      RawNotification(
        id: id ?? 'n${n++}',
        sender: pkg == null ? sender : title,
        title: title,
        packageName: pkg,
        body: body,
        receivedAt: now.subtract(ago),
      ),
    );
    return r.isDuplicate ? null : r.persistedTransactionId;
  }

  Future<List<LedgerTransaction>> entries() =>
      db.transactionsDao.getAllTransactions();

  Future<StsBreakdown> sts({
    bool paidMarksStale = false,
    bool salaryDueNow = false,
    int keepUntouched = 0,
  }) async => StsBreakdown.compute(
    salaryDueNow: salaryDueNow,
    keepUntouched: keepUntouched,
    buckets: await db.accountsDao.getAllBuckets(),
    accounts: await db.accountsDao.getAllActivePhysicalAccounts(),
    mandates: const [],
    dues: await db.select(db.dues).get(),
    cycle: Paycycle.fromSalaryDay(salaryCreditDay: 1, asOf: now),
    reserveCards: true,
    includeOwed: false,
    salaryAccountId: await db.settingsDao.get(SettingKeys.salaryAccount),
    pending: (await db.transactionsDao.getAllTransactions())
        .where((t) => t.transactionState == TransactionState.needsReview)
        .toList(),
    paidMarksStale: paidMarksStale,
    now: now,
  );

  setUp(() async {
    db = RiveroDatabase.memory();
    await ensureDefaults(db); // captures wait for Accept, like the app
    capture = IngestionService(database: db);
    ledger = LedgerService(db);
    plan = SalaryPlanService(db);
  });
  tearDown(() => db.close());

  test('H1: captures accepted in any order give the same balance', () async {
    await account('bank', 100000, mask: '4012');
    final older = await sms(
      'Rs 200.00 debited from A/c XX4012 to VPA tea@ybl (UPI Ref No '
      '100000000001). Avl bal: Rs 800.00',
      ago: const Duration(hours: 2),
    );
    final newer = await sms(
      'Rs 300.00 debited from A/c XX4012 to VPA lunch@ybl (UPI Ref No '
      '100000000002). Avl bal: Rs 500.00',
      ago: const Duration(hours: 1),
    );
    await ledger.confirm(newer!);
    expect(await bal('bank'), 70000); // only its amount; "Avl bal" ignored
    await ledger.confirm(older!);
    expect(await bal('bank'), 50000);
    // In time order it is the same answer.
  });

  test('H1: accepting in time order still follows each bank balance', () async {
    await account('bank', 100000, mask: '4012');
    final a = await sms(
      'Rs 200.00 debited from A/c XX4012 to VPA tea@ybl (UPI Ref No '
      '100000000001). Avl bal: Rs 800.00',
      ago: const Duration(hours: 2),
    );
    final b = await sms(
      'Rs 300.00 debited from A/c XX4012 to VPA lunch@ybl (UPI Ref No '
      '100000000002).', // no balance in this one
      ago: const Duration(hours: 1),
    );
    await ledger.confirm(a!);
    expect(await bal('bank'), 80000);
    await ledger.confirm(b!);
    expect(await bal('bank'), 50000);
  });

  test(
    'H2: a typed balance is not reduced by an older capture accepted later',
    () async {
      await account('bank', 100000, mask: '4012');
      final old = await sms(
        'Rs 200.00 debited from A/c XX4012 to VPA tea@ybl (UPI Ref No '
        '100000000001).',
        ago: const Duration(hours: 5),
      );
      await ledger.setBalance('bank', 80000); // the real balance, typed now
      await ledger.confirm(old!);
      expect(await bal('bank'), 80000);
      // Deleting that older entry does not move the stated balance either.
      await ledger.remove(old);
      expect(await bal('bank'), 80000);
      // A new spend after the update still counts.
      await ledger.recordManual(
        accountId: 'bank',
        amountMinorUnits: -5000,
        type: TransactionType.expense,
        merchant: 'Chai',
        category: 'Food',
      );
      expect(await bal('bank'), 75000);
    },
  );

  test(
    'H3: accounts without last digits are not multiplied by captures',
    () async {
      await account('sbi', 500000, mask: '0000'); // what older versions saved
      await account('icici', 300000);
      await sms(
        'Rs 250.00 debited from A/c XX4321 to VPA shop@ybl (UPI Ref No '
        '100000000003).',
      );
      final all = await db.accountsDao.getAllActivePhysicalAccounts();
      expect(all.map((a) => a.id), unorderedEquals(['sbi', 'icici']));
      // Two possible accounts: a guess, so it waits for review.
      final t = (await db.transactionsDao.getAllTransactions()).single;
      expect(t.transactionState, TransactionState.needsReview);
    },
  );

  test('H3: the only bank account learns its digits', () async {
    await account('sbi', 500000, mask: '0000');
    await sms(
      'Rs 250.00 debited from A/c XX4321 to VPA shop@ybl (UPI Ref No '
      '100000000003).',
    );
    expect(
      (await db.accountsDao.getPhysicalAccountById('sbi'))!.accountMask,
      '4321',
    );
  });

  test('H4: salary in, not split yet: rent is held back again', () async {
    await account('sbi', 5800000, mask: '1111', type: 'Salary');
    await db.settingsDao.set(SettingKeys.salaryAccount, 'sbi');
    final rent = await plan.addCustomCategory('Rent', 1500000);
    await plan.apply(
      salary: 5000000,
      allocations: {rent: 1500000, 'bucket-expense': 3500000},
      cycleStart: DateTime(now.year, now.month - 1),
    );
    await plan.markAlreadyPaid(rent); // paid LAST cycle
    expect((await sts()).reservedInAccount, 0);
    final b = await sts(paidMarksStale: true);
    expect(b.reservedInAccount, 1500000);
    expect(b.usable, 5800000 - 1500000);
  });

  test(
    'H5: rent marked "Paying now", bank message a day later: counted once',
    () async {
      await account('sbi', 5000000, mask: '1111', type: 'Salary');
      await db.settingsDao.set(SettingKeys.salaryAccount, 'sbi');
      final rent = await plan.addCustomCategory('Rent', 1500000);
      await plan.apply(
        salary: 5000000,
        allocations: {rent: 1500000, 'bucket-expense': 3500000},
        cycleStart: Paycycle.fromSalaryDay(
          salaryCreditDay: 1,
          asOf: now,
        ).cycleStartDate,
      );
      await ledger.recordManual(
        accountId: 'sbi',
        amountMinorUnits: -1500000,
        type: TransactionType.planTransfer,
        merchant: 'Plan: Rent',
        category: 'Rent',
        bucketId: rent,
        at: now.subtract(const Duration(days: 1)),
      );
      final again = await sms(
        'Rs 15,000.00 debited from A/c XX1111 to VPA landlord@ybl (UPI Ref No '
        '120000000001).',
      );
      expect(again, isNull); // recognised as the same payment
      expect(await db.transactionsDao.getAllTransactions(), hasLength(1));
    },
  );

  test('H6: a loan is not a card bill', () async {
    await account('bank', 1000000, mask: '4012');
    await plan.setRouting(spendingAccountId: 'bank');
    await account(
      'homeloan',
      -250000000,
      card: true,
      type: StandardAccountTypes.loan,
    );
    await account('card', -200000, card: true, mask: '7102');
    final b = await sts();
    expect(b.cardBillsTotal, 200000);
    expect(b.result.isDeficit, isFalse);
  });

  test(
    'H7: a payment waiting for Accept already lowers Safe to spend',
    () async {
      await account('bank', 1000000, mask: '4012');
      await plan.setRouting(spendingAccountId: 'bank');
      final id = await sms(
        'Rs 6,000.00 debited from A/c XX4012 to VPA shop@ybl (UPI Ref No '
        '700000000002). Avl bal: Rs 4,000.00',
      );
      var b = await sts();
      expect(b.waitingInAccount, 600000);
      expect(b.usable, 400000);
      // Accepting changes nothing: it moves from "waiting" into the balance.
      await ledger.confirm(id!);
      b = await sts();
      expect(b.waitingInAccount, 0);
      expect(b.usable, 400000);
    },
  );

  test('H7: ignoring a waiting payment gives the money back', () async {
    await account('bank', 1000000, mask: '4012');
    await plan.setRouting(spendingAccountId: 'bank');
    final id = await sms(
      'Rs 6,000.00 debited from A/c XX4012 to VPA shop@ybl (UPI Ref No '
      '700000000002).',
    );
    expect((await sts()).usable, 400000);
    await ledger.ignore(id!);
    expect((await sts()).usable, 1000000);
  });

  test(
    'H7: a waiting payment older than a typed balance is not counted',
    () async {
      await account('bank', 1000000, mask: '4012');
      await plan.setRouting(spendingAccountId: 'bank');
      await sms(
        'Rs 6,000.00 debited from A/c XX4012 to VPA shop@ybl (UPI Ref No '
        '700000000002).',
        ago: const Duration(hours: 3),
      );
      await ledger.setBalance('bank', 400000);
      final b = await sts();
      expect(b.waitingInAccount, 0);
      expect(b.usable, 400000);
    },
  );

  // ---- medium and low items of the same audit --------------------------

  const gpay = 'com.google.android.apps.nbu.paisa.user';

  test('H6: a custom "Home Loan" type is not a card bill either', () async {
    await account('bank', 1000000, mask: '4012');
    await plan.setRouting(spendingAccountId: 'bank');
    await account('loan', -250000000, card: true, type: 'Home Loan');
    expect((await sts()).cardBillsTotal, 0);
  });

  test('M1: no plan yet: a logged spend is not a shortfall', () async {
    await account('bank', 500000, mask: '4012');
    await ledger.recordManual(
      accountId: 'bank',
      amountMinorUnits: -20000,
      type: TransactionType.expense,
      merchant: 'Chai',
      category: 'Food',
    );
    final b = await sts();
    expect(b.hasPlan, isFalse);
    expect(b.usable, 0);
    expect(b.result.isDeficit, isFalse);
  });

  test('M2: pay day, salary not in yet: what is left lasts until it '
      'lands', () async {
    await account('bank', 200000, mask: '4012');
    await plan.setRouting(spendingAccountId: 'bank');
    expect((await sts(salaryDueNow: true)).result.dailySpendingPace, 200000);
    expect((await sts()).result.dailySpendingPace, lessThanOrEqualTo(200000));
  });

  test('M3: money kept untouched is never safe to spend', () async {
    await account('bank', 1000000, mask: '4012');
    await plan.setRouting(spendingAccountId: 'bank');
    final b = await sts(keepUntouched: 700000);
    expect(b.keptUntouched, 700000);
    expect(b.usable, 300000);
  });

  test('M4: two payments of one amount from the same app, to different '
      'people, are two payments', () async {
    await account('bank', 100000, mask: '4012');
    await sms(
      'Paid ₹100.00 to Ravi',
      pkg: gpay,
      title: 'Google Pay',
      ago: const Duration(seconds: 50),
    );
    await sms('Paid ₹100.00 to Sita', pkg: gpay, title: 'Google Pay');
    expect(await entries(), hasLength(2));
    // The bank's SMS for the second one is still the same payment.
    final again = await sms(
      'Rs 100.00 debited from A/c XX4012 to VPA sita@ybl (UPI Ref No '
      '400000000001).',
    );
    expect(again, isNull);
    expect(await entries(), hasLength(2));
  });

  test(
    'M5: an old plan move does not swallow a real payment months later',
    () async {
      await account('sbi', 5000000, mask: '1111', type: 'Salary');
      await account('icici', 0, mask: '5678');
      await db.settingsDao.set(SettingKeys.salaryAccount, 'sbi');
      await plan.setRouting(spendingAccountId: 'icici');
      await plan.apply(
        salary: 5000000,
        allocations: {'bucket-expense': 500000},
        cycleStart: DateTime(now.year, now.month - 2),
        moveMoney: true,
      );
      // Back-date the move: it was made two cycles ago.
      await (db.update(
        db.transactions,
      )..where((t) => t.id.like('plan-%'))).write(
        TransactionsCompanion(
          transactionTimestamp: Value(now.subtract(const Duration(days: 60))),
        ),
      );
      expect(await bal('sbi'), 4500000);
      final real = await sms(
        'Rs 5,000.00 debited from A/c XX1111 to VPA doctor@ybl (UPI Ref No '
        '500000000001).',
        sender: 'VM-SBIINB',
      );
      expect(real, isNotNull); // a payment of its own, waiting for Accept
      await ledger.confirm(real!);
      expect(await bal('sbi'), 4000000);
    },
  );

  group('M6: card bill, the card message first', () {
    Future<void> bill() async {
      await account('bank', 1000000, mask: '4012');
      await account('card', -500000, mask: '7102', card: true);
      await sms(
        'Payment of Rs 5,000.00 received towards your Credit Card XX7102. '
        'Ref 110000000001',
        sender: 'VM-HDFCCC',
        ago: const Duration(hours: 1),
      );
      await sms(
        'Rs 5,000.00 debited from A/c XX4012 towards HDFC Credit Card '
        'XX7102. UPI Ref No 110000000002.',
      );
    }

    test('nothing moves until it is accepted, then both sides do', () async {
      await bill();
      expect(await bal('bank'), 1000000);
      expect(await bal('card'), -500000);
      final bankSide = (await entries()).firstWhere(
        (t) => t.physicalAccountId == 'bank',
      );
      expect(bankSide.transactionState, TransactionState.needsReview);
      await ledger.confirm(bankSide.id);
      expect(await bal('bank'), 500000);
      expect(await bal('card'), 0);
    });

    test('ignoring it ignores both sides', () async {
      await bill();
      final cardSide = (await entries()).firstWhere(
        (t) => t.physicalAccountId == 'card',
      );
      await ledger.ignore(cardSide.id);
      expect(
        (await entries()).map((t) => t.transactionState),
        everyElement(TransactionState.ignored),
      );
      expect(await bal('bank'), 1000000);
      expect(await bal('card'), -500000);
    });
  });

  test('M7: a slow transfer between own accounts is not spend plus '
      'income', () async {
    await account('sbi', 2000000, mask: '1111', type: 'Salary');
    await account('icici', 100000, mask: '5678');
    final out = await sms(
      'Rs 5,000.00 debited from A/c XX1111 trf to PARTHIV K Ref No '
      '800000000001',
      sender: 'VM-SBIINB',
      ago: const Duration(minutes: 40),
    );
    final inn = await sms(
      'Rs 5,000.00 credited to A/c XX5678 by IMPS from PARTHIV K Ref '
      '900000000009',
      sender: 'VM-ICICIB',
    );
    await ledger.confirm(out!);
    await ledger.confirm(inn!);
    await ReconciliationService(database: db).reconcileAll();
    final all = await entries();
    expect(all.map((t) => t.isInternalTransfer), everyElement(isTrue));
    final spending = (await db.accountsDao.getAllBuckets()).firstWhere(
      (b) => b.id == 'bucket-expense',
    );
    expect(spending.spentMinorUnits, 0);
  });

  test('M8: a choice on the second notification of one payment reaches '
      'the entry, and never removes it', () async {
    await account('bank', 100000, mask: '4012');
    final first = await sms(
      'Paid ₹300.00 to Cafe',
      pkg: 'com.phonepe.app',
      title: 'PhonePe',
      ago: const Duration(seconds: 20),
      id: 'push',
    );
    await sms(
      'Rs 300.00 debited from A/c XX4012 to VPA cafe@ybl (UPI Ref No '
      '700000000001).',
      id: 'bank-sms',
    );
    final decisions = CaptureDecisions(db);
    expect(
      await decisions.apply({
        'bank-sms': {'action': 'ignore'},
      }),
      0,
    );
    expect(
      (await entries()).single.transactionState,
      TransactionState.needsReview,
    );
    await decisions.apply({
      'bank-sms': {'action': 'add', 'category': 'Food', 'note': null},
    });
    final t = (await entries()).single;
    expect(t.id, first);
    expect(t.transactionState, isNot(TransactionState.needsReview));
    expect(t.category, 'Food');
    expect(await bal('bank'), 70000);
    // Settled: the same choice again changes nothing.
    await decisions.apply({
      'bank-sms': {'action': 'ignore'},
    });
    expect(await entries(), hasLength(1));
  });

  test('M10: the balance in a bank SMS is never taken, whichever message '
      'came first', () async {
    await account('bank', 100000, mask: '4012');
    final a = await sms(
      'Paid ₹300.00 to Cafe',
      pkg: 'com.phonepe.app',
      title: 'PhonePe',
      ago: const Duration(seconds: 20),
    );
    await sms(
      'Rs 300.00 debited from A/c XX4012 to VPA cafe@ybl (UPI Ref No '
      '700000000001). Avl bal: Rs 650.00',
    );
    await ledger.confirm(a!);
    // ₹1,000 - ₹300: the user's balance moved by the amount. The bank's
    // "Avl bal: Rs 650.00" is not taken (messages are missed or misread).
    expect(await bal('bank'), 70000);
  });

  test('M11: borrowed money with no pay-back date is not safe to '
      'spend', () async {
    await account('bank', 100000, mask: '4012');
    await plan.setRouting(spendingAccountId: 'bank');
    final before = (await sts()).result.effectiveSafeToSpend;
    await DuesService(db)
        .borrow(person: 'Ravi', amountMinorUnits: 500000, accountId: 'bank');
    expect(await bal('bank'), 600000);
    expect((await sts()).result.effectiveSafeToSpend, before);
  });

  test('M14: deleting a spend that hit zero gives back only what it '
      'took', () async {
    await account('bank', 30000, mask: '4012');
    final id = await ledger.recordManual(
      accountId: 'bank',
      amountMinorUnits: -50000,
      type: TransactionType.expense,
      merchant: 'Shoes',
      category: 'Shopping',
    );
    expect(await bal('bank'), 0);
    await ledger.remove(id);
    expect(await bal('bank'), 30000);
  });

  test('L1: cash from an ATM lands in the Cash account, and is not '
      'spent yet', () async {
    await account('bank', 1000000, mask: '4012');
    await account('cash', 0, type: StandardAccountTypes.cash);
    final a = await sms(
      'Rs 2,000.00 withdrawn from A/c XX4012 at ATM on 15-11-26.',
    );
    await ledger.confirm(a!);
    expect(await bal('bank'), 800000);
    expect(await bal('cash'), 200000);
    Future<int> spent() async => (await db.accountsDao.getAllBuckets())
        .firstWhere((b) => b.id == 'bucket-expense')
        .spentMinorUnits;
    expect(await spent(), 0);
    // Deleting the withdrawal undoes both sides.
    await ledger.removeWithPlanPartner(a);
    expect(await bal('bank'), 1000000);
    expect(await bal('cash'), 0);
    expect(await entries(), isEmpty);
  });

  test('L1: spending the cash is the spend', () async {
    await account('bank', 1000000, mask: '4012');
    await account('cash', 0, type: StandardAccountTypes.cash);
    final a = await sms(
      'Rs 2,000.00 withdrawn from A/c XX4012 at ATM on 15-11-26.',
    );
    await ledger.confirm(a!);
    Future<int> spent() async => (await db.accountsDao.getAllBuckets())
        .firstWhere((b) => b.id == 'bucket-expense')
        .spentMinorUnits;
    await ledger.recordManual(
      accountId: 'cash',
      amountMinorUnits: -50000,
      type: TransactionType.cashExpenditure,
      merchant: 'Vegetables',
      category: 'Food',
    );
    expect(await spent(), 50000);
    expect(await bal('cash'), 150000);
  });

  test('L1: without a Cash account an ATM withdrawal is a spend', () async {
    await account('bank', 1000000, mask: '4012');
    final a = await sms(
      'Rs 2,000.00 withdrawn from A/c XX4012 at ATM on 15-11-26.',
    );
    await ledger.confirm(a!);
    expect(await entries(), hasLength(1));
    expect(await bal('bank'), 800000);
  });

  test('L2: a card Rivero adds itself is not named "Card Card"', () async {
    await account('bank', 1000000, mask: '4012');
    await sms(
      'INR 2,500.00 spent on Credit Card XX9999 at FLIPKART on 15-11-26. '
      'Ref 600000000002',
      sender: 'VM-AXISCC',
    );
    final names = (await db.accountsDao.getAllActivePhysicalAccounts()).map(
      (a) => a.name,
    );
    expect(names.where((x) => x.contains('Card Card')), isEmpty);
    expect(names.where((x) => x.contains('9999')), hasLength(1));
  });

  // ---- notification pop-up (approve from the notification) -------------

  group('Pop-up: app notification and a later bank SMS are one payment', () {
    Future<List<LedgerTransaction>> waiting() async => (await entries())
        .where((t) => t.transactionState == TransactionState.needsReview)
        .toList();

    for (final gap in [90, 240, 1500]) {
      test('SMS ${gap}s later, other payee name: Add on the pop-up '
          'leaves nothing to review', () async {
        await account('bank', 100000, mask: '4012');
        await sms(
          'Paid ₹300.00 to Cafe Coffee Day',
          pkg: gpay,
          title: 'Google Pay',
          ago: Duration(seconds: gap),
          id: 'push',
        );
        await sms(
          'Rs 300.00 debited from A/c XX4012 to VPA ccdpayments@icici (UPI '
          'Ref No 700000000001).',
          id: 'bank-sms',
        );
        expect(await entries(), hasLength(1));
        await CaptureDecisions(db).apply({
          'push': {'action': 'accept', 'category': 'Food', 'note': null},
        });
        expect(await waiting(), isEmpty);
        final t = (await entries()).single;
        expect(t.category, 'Food');
        expect(t.referenceNumber, '700000000001');
        expect(await bal('bank'), 70000);
      });
    }

    test('bank SMS first, the app notification after', () async {
      await account('bank', 100000, mask: '4012');
      await sms(
        'Rs 300.00 debited from A/c XX4012 to VPA ccdpayments@icici (UPI '
        'Ref No 700000000001).',
        ago: const Duration(minutes: 2),
      );
      await sms('Paid ₹300.00 to Cafe Coffee Day', pkg: gpay, title: 'GPay');
      expect(await entries(), hasLength(1));
    });

    test('two real payments of one amount stay two', () async {
      await account('bank', 100000, mask: '4012');
      await sms(
        'Paid ₹300.00 to Cafe Coffee Day',
        pkg: gpay,
        title: 'Google Pay',
        ago: const Duration(minutes: 12),
      );
      await sms(
        'Rs 300.00 debited from A/c XX4012 to VPA ccdpayments@icici (UPI '
        'Ref No 700000000001).',
        ago: const Duration(minutes: 9),
      );
      await sms(
        'Paid ₹300.00 to Pizza Hub',
        pkg: 'com.phonepe.app',
        title: 'PhonePe',
        ago: const Duration(minutes: 2),
      );
      await sms(
        'Rs 300.00 debited from A/c XX4012 to VPA pizzahub@okaxis (UPI Ref '
        'No 700000000002).',
      );
      final all = await entries();
      expect(all, hasLength(2));
      expect(
        all.map((t) => t.referenceNumber),
        unorderedEquals(['700000000001', '700000000002']),
      );
    });

    test('the bank SMS corrects the account the app guessed', () async {
      await account('sbi', 500000, mask: '1111');
      await account('hdfc', 500000, mask: '4012');
      await sms(
        'Paid ₹300.00 to Cafe Coffee Day',
        pkg: gpay,
        title: 'Google Pay',
        ago: const Duration(minutes: 3),
      );
      await sms(
        'Rs 300.00 debited from A/c XX4012 to VPA ccdpayments@icici (UPI '
        'Ref No 700000000001).',
      );
      expect((await entries()).single.physicalAccountId, 'hdfc');
    });
  });

  group('Pop-up on a message Rivero could not read', () {
    const odd = 'Your a/c 4012 txn of INR300 at CCD done';

    test('Add keeps the category and note for adding it from Home', () async {
      await sms(
        odd,
        pkg: 'com.google.android.apps.messaging',
        title: 'HDFCBK',
        id: 'odd',
      );
      expect(
        await CaptureDecisions(db).apply({
          'odd': {'action': 'accept', 'category': 'Food', 'note': 'Coffee'},
        }),
        1,
      );
      final kept = await CaptureDecisions.unreadableChoices(db);
      final p = LogPrefill.fromMessage(odd)
          .withChoice((kept['odd'] as Map).cast<String, dynamic>());
      expect(p.category, 'Food');
      expect(p.note, 'Coffee');
      expect(p.amountText, '300');
      // Still waiting under "bank messages to check".
      expect(await db.ingestionLogsDao.watchUnreadable().first, hasLength(1));
    });

    test('Ignore dismisses it', () async {
      await sms(
        odd,
        pkg: 'com.google.android.apps.messaging',
        title: 'HDFCBK',
        id: 'odd',
      );
      await CaptureDecisions(db).apply({
        'odd': {'action': 'ignore'},
      });
      expect(await db.ingestionLogsDao.watchUnreadable().first, isEmpty);
    });
  });

  // ---- pop-up "Add" when the notification has an awkward title ---------

  group('Pop-up Add reaches the transaction list', () {
    Future<void> drainOne(String id, String? title, String body) =>
        NotificationBridge(capture).ingestJson(
          jsonEncode([
            {
              'id': id,
              'package': gpay,
              'title': title,
              'body': body,
              'time': now.millisecondsSinceEpoch,
            },
          ]),
        );

    for (final title in [
      'You paid ₹500.00 to Ravi Kumar from your HDFC Bank account',
      '',
    ]) {
      test('title "${title.isEmpty ? '(empty)' : 'long'}"', () async {
        await account('bank', 100000, mask: '4012');
        await drainOne('pop-1', title, 'UPI ID ravi@okhdfc · ₹500.00');
        expect(
          await CaptureDecisions(db).apply({
            'pop-1': {'action': 'accept', 'category': 'Food', 'note': null},
          }),
          1,
        );
        final t = (await entries()).single;
        expect(t.transactionState, isNot(TransactionState.needsReview));
        expect(t.category, 'Food');
      });
    }

    test(
      'a choice made before its notification is processed waits for it',
      () async {
        await account('bank', 100000, mask: '4012');
        final decisions = CaptureDecisions(db);
        expect(
          await decisions.apply({
            'pop-2': {'action': 'accept', 'category': 'Fun', 'note': 'Movie'},
          }),
          0,
        );
        await drainOne('pop-2', 'Google Pay', 'Paid ₹300.00 to PVR');
        expect(await decisions.apply({}), 1); // the next capture run
        final t = (await entries()).single;
        expect(t.category, 'Fun');
        expect(t.userNotes, 'Movie');
        expect(t.transactionState, isNot(TransactionState.needsReview));
      },
    );
  });

  // ---- the real Union Bank SMS (15 Nov 2026) ---------------------------

  group('Union Bank SMS from JX-UNIONB-S via Samsung Messages', () {
    const body =
        'Union Bank of India A/c*0485 Dr Rs25.00 on 15-11-26 19:19 by MB '
        '631977745590 Fv.IRANI, Bal Rs701.83 Not U?Call 18002333/SMS BLOCK '
        '0485 to 8879635472';
    Future<void> arrive(String id, String title) => NotificationBridge(capture)
        .ingestJson(
          jsonEncode([
            {
              'id': id,
              'package': 'com.samsung.android.messaging',
              'title': title,
              'body': body,
              'time': now.millisecondsSinceEpoch,
            },
          ]),
        );

    test('the sender with its "-S" suffix is a bank', () {
      expect(
        const TraiDltValidator().isFinancialSender(senderHeader: 'JX-UNIONB-S'),
        isTrue,
      );
      expect(
        const TraiDltValidator().isFinancialSender(senderHeader: 'VM-HDFCBK-T'),
        isTrue,
      );
    });

    test('pop-up Add records it in Activity', () async {
      await account('ubi', 100000, mask: '0485');
      await arrive('ubi-1', 'JX-UNIONB-S');
      await CaptureDecisions(db).apply({
        'ubi-1': {'action': 'accept', 'category': 'Food', 'note': null},
      });
      final t = (await entries()).single;
      expect(t.transactionState, isNot(TransactionState.needsReview));
      expect(t.merchant, 'IRANI');
      expect(t.category, 'Food');
      expect(t.amountMinorUnits, -2500);
      expect(t.physicalAccountId, 'ubi');
    });

    test('already logged by hand: the pop-up files that entry, nothing is '
        'counted twice', () async {
      await account('ubi', 100000, mask: '0485');
      final typed = await ledger.recordManual(
        accountId: 'ubi',
        amountMinorUnits: -2500,
        type: TransactionType.expense,
        merchant: 'Other',
        category: 'Other',
        at: now.subtract(const Duration(hours: 1)),
      );
      await arrive('ubi-2', '+919701122455'); // forwarded copy
      await CaptureDecisions(db).apply({
        'ubi-2': {'action': 'accept', 'category': 'Food', 'note': 'Sandwich'},
      });
      final all = await entries();
      expect(all, hasLength(1));
      expect(all.single.id, typed);
      expect(all.single.category, 'Food');
      expect(all.single.userNotes, 'Sandwich');
      // Counted once; the "Bal Rs701.83" in the message is not taken.
      expect(await bal('ubi'), 97500);
    });
  });

  // ---- deleting an entry whose message stated the balance --------------

  group('Deleting a captured payment puts the balance back as it was', () {
    String ubi(String amount) =>
        'Union Bank of India A/c*0485 Dr Rs$amount on 15-11-26 19:19 by MB '
        '631977745590 Fv.IRANI, Bal Rs701.83 Not U?Call 18002333/SMS BLOCK '
        '0485 to 8879635472';

    for (final amount in ['275.00', '2105.00']) {
      test('edited test message "Dr Rs$amount ... Bal Rs701.83"', () async {
        await account('ubi', 300000, mask: '0485'); // ₹3,000 before
        final id = await sms(ubi(amount), sender: 'JX-UNIONB-S');
        await ledger.confirm(id!);
        // Only the amount; the message's "Bal Rs701.83" is not taken.
        expect(await bal('ubi'), 300000 - (double.parse(amount) * 100).round());
        await ledger.remove(id);
        expect(await bal('ubi'), 300000); // as before the message
      });
    }

    test('automatic acceptance on: the same', () async {
      await db.settingsDao.set(SettingKeys.captureAutoAccept, '1');
      await account('ubi', 300000, mask: '0485');
      final id = await sms(ubi('25.00'), sender: 'JX-UNIONB-S');
      expect(await bal('ubi'), 297500);
      await ledger.remove(id!);
      expect(await bal('ubi'), 300000);
    });

    test('a later payment keeps the balance it brought', () async {
      await account('ubi', 300000, mask: '0485');
      final first = await sms(
        ubi('25.00'),
        sender: 'JX-UNIONB-S',
        ago: const Duration(hours: 1),
      );
      await ledger.confirm(first!);
      await ledger.recordManual(
        accountId: 'ubi',
        amountMinorUnits: -10000,
        type: TransactionType.expense,
        merchant: 'Tea',
        category: 'Food',
      );
      expect(await bal('ubi'), 287500);
      await ledger.remove(first);
      // The ₹100 tea stays spent; only the deleted message is undone.
      expect(await bal('ubi'), 290000);
    });
  });
}
