import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/plan/defaults.dart';

import '../../test_helper.dart';

/// Capture fixes from the 14 Nov 2026 audit.
void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  late IngestionService capture;
  final at = DateTime(2026, 11, 14, 10);
  var n = 0;

  Future<void> account(
    String id,
    int balance, {
    String mask = '••••',
    bool card = false,
  }) => db.accountsDao.upsertPhysicalAccount(
    PhysicalAccountsCompanion(
      id: Value(id),
      name: Value(id),
      institution: const Value('Bank'),
      accountMask: Value(mask),
      balanceMinorUnits: Value(balance),
      isLiability: Value(card),
      createdAt: Value(at),
      updatedAt: Value(at),
    ),
  );

  Future<RawNotification> sms(String body, {Duration after = Duration.zero}) =>
      Future.value(
        RawNotification(
          id: 'n${n++}',
          sender: 'VM-HDFCBK',
          body: body,
          receivedAt: at.add(after),
        ),
      );

  Future<int> bal(String id) async =>
      (await db.accountsDao.getPhysicalAccountById(id))!.balanceMinorUnits;
  Future<List<LedgerTransaction>> all() =>
      db.transactionsDao.getAllTransactions();

  setUp(() {
    db = RiveroDatabase.memory();
    capture = IngestionService(database: db);
  });
  tearDown(() => db.close());

  group('H2: card bill paid from the bank', () {
    setUp(() async {
      await account('bank', 10000000, mask: '4012');
      await account('card', -500000, mask: '7102', card: true);
    });

    test('lowers what the card owes, once', () async {
      await capture.processNotification(
        await sms(
          'Rs 5,000.00 debited from A/c XX4012 towards HDFC Credit Card '
          'XX7102 bill payment. UPI Ref No 612345678901. Avl bal: Rs 95,000.00',
        ),
      );
      expect(await bal('bank'), 9500000);
      expect(await bal('card'), 0);
      // The card's own message later is the same payment, not a second one.
      await capture.processNotification(
        await sms(
          'Payment of Rs 5,000.00 received towards your Credit Card XX7102. '
          'Thank you.',
          after: const Duration(hours: 5),
        ),
      );
      expect(await bal('card'), 0);
      expect((await all()).length, 2);
    });

    test('card message first, then the bank: paired, not doubled', () async {
      await capture.processNotification(
        await sms(
          'Payment of Rs 5,000.00 received towards your Credit Card XX7102. '
          'Ref 998877665544.',
        ),
      );
      expect(await bal('card'), 0);
      await capture.processNotification(
        await sms(
          'Rs 5,000.00 debited from A/c XX4012 towards HDFC Credit Card '
          'XX7102. UPI Ref No 612345678901.',
          after: const Duration(hours: 2),
        ),
      );
      expect(await bal('card'), 0);
      expect(await bal('bank'), 9500000);
      final legs = await all();
      expect(legs, hasLength(2));
      expect(legs.every((t) => t.linkedTransactionId != null), isTrue);
    });

    test('deleting one leg removes both', () async {
      await capture.processNotification(
        await sms(
          'Rs 5,000.00 debited from A/c XX4012 towards HDFC Credit Card '
          'XX7102 bill. UPI Ref No 612345678901.',
        ),
      );
      final bankLeg = (await all()).firstWhere(
        (t) => t.physicalAccountId == 'bank',
      );
      await LedgerService(db).removeWithPlanPartner(bankLeg.id);
      expect(await all(), isEmpty);
      expect(await bal('bank'), 10000000);
      expect(await bal('card'), -500000);
    });
  });

  group('H3: which account', () {
    test('a bank message never lands on a card', () async {
      await account('card', 0, mask: '7102', card: true);
      await account('bank', 100000);
      await capture.processNotification(
        await sms('Rs 200.00 debited from A/c XX9999. UPI Ref 612345678901.'),
      );
      final t = (await all()).single;
      expect(t.physicalAccountId, 'bank');
      // The only bank account learns its digits for next time.
      expect(
        (await db.accountsDao.getPhysicalAccountById('bank'))!.accountMask,
        '9999',
      );
    });

    test('a guess between several banks waits for review', () async {
      await account('a', 100000);
      await account('b', 100000);
      await capture.processNotification(
        await sms('Rs 200.00 debited from A/c XX9999. UPI Ref 612345678901.'),
      );
      final t = (await all()).single;
      expect(t.transactionState, TransactionState.needsReview);
      expect(await bal('a'), 100000);
      expect(await bal('b'), 100000);
    });
  });

  group('M1/M2: duplicates', () {
    setUp(() => account('bank', 100000, mask: '4012'));

    test(
      'two teas a minute apart with different references both count',
      () async {
        await capture.processNotification(
          await sms(
            'Rs 20.00 debited from A/c XX4012 to TEA STALL. '
            'UPI Ref No 612345678901.',
          ),
        );
        await capture.processNotification(
          await sms(
            'Rs 20.00 debited from A/c XX4012 to TEA STALL. '
            'UPI Ref No 612345678902.',
            after: const Duration(seconds: 40),
          ),
        );
        expect(await all(), hasLength(2));
        expect(await bal('bank'), 96000);
      },
    );

    test(
      "a spend logged by hand hours earlier is the bank's message",
      () async {
        await LedgerService(db).recordManual(
          accountId: 'bank',
          amountMinorUnits: -45000,
          type: TransactionType.expense,
          merchant: 'Groceries',
          category: 'Food',
          at: at,
        );
        await capture.processNotification(
          await sms(
            'Rs 450.00 debited from A/c XX4012 to DMART. UPI Ref No '
            '612345678901. Avl bal: Rs 550.00',
            after: const Duration(hours: 3),
          ),
        );
        final txns = await all();
        expect(txns, hasLength(1));
        expect(txns.single.referenceNumber, '612345678901');
        expect(await bal('bank'), 55000);
      },
    );
  });

  test('M14: an unsure promotion is not put up for review', () async {
    await account('bank', 100000, mask: '4012');
    final r = await capture.processNotification(
      RawNotification(
        id: 'promo',
        packageName: 'com.samsung.android.messaging',
        title: 'AD-OFFERS',
        sender: 'AD-OFFERS',
        body: 'Get Rs 500 cashback when you pay your bills with us!',
        receivedAt: at,
      ),
    );
    expect(r.status, ParseStatus.failed);
    expect(await all(), isEmpty);
  });

  test('L1: a failed autopay message is shown, never dropped', () async {
    final r = await capture.processNotification(
      RawNotification(
        id: 'fail',
        sender: 'VM-HDFCBK',
        body:
            'Your autopay of Rs 649 to Netflix failed due to insufficient '
            'balance.',
        receivedAt: DateTime.now(),
      ),
    );
    expect(r.status, ParseStatus.failed);
    final shown = await db.ingestionLogsDao.watchUnreadable().first;
    expect(shown.single.id, 'fail');
    expect(await all(), isEmpty); // not a transaction
  });

  group('review first', () {
    const body =
        'Rs 450.00 debited from A/c XX4012 to VPA swiggy@hdfcbank '
        '(UPI Ref No 431712345678). Avl bal: Rs 45,000.00';

    test(
      'with the app default, even a confident capture waits for Accept',
      () async {
        await account('bank', 5000000, mask: '4012');
        await ensureDefaults(db); // sets review-first
        await capture.processNotification(await sms(body));
        final t = (await all()).single;
        expect(t.transactionState, TransactionState.needsReview);
        expect(await bal('bank'), 5000000); // nothing moved yet
        // Accept applies it once and adopts the bank's balance.
        await LedgerService(db).confirm(t.id);
        expect(await bal('bank'), 4500000);
      },
    );

    test(
      'automatic acceptance lets confident captures straight through',
      () async {
        await account('bank', 5000000, mask: '4012');
        await ensureDefaults(db);
        await db.settingsDao.set(SettingKeys.captureAutoAccept, '1');
        await capture.processNotification(await sms(body));
        expect(
          (await all()).single.transactionState,
          TransactionState.confirmed,
        );
        expect(await bal('bank'), 4500000);
      },
    );
  });
}
