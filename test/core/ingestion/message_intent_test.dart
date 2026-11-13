import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/ingestion_result.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ingestion/parser/financial_parser.dart';
import 'package:rivero/core/ingestion/parser/message_intent.dart';

import '../../test_helper.dart';

const _predebit =
    'Dear Customer, Rs 649.00 will be debited from your A/c XX4012 on 16-Nov-26 towards Netflix via UPI Autopay mandate. Ensure sufficient balance.';
const _created =
    'You have successfully created a UPI Autopay mandate for Rs 199.00 monthly to Spotify from A/c XX4012. UMN: abc123@okhdfc';
const _cancelled =
    'Your UPI mandate for Netflix Rs 649 has been revoked successfully.';
const _failed =
    'Autopay of Rs 649 to Netflix failed due to insufficient balance in A/c XX4012.';
const _otp =
    'Your OTP for txn of Rs 2,500.00 at AMAZON is 482913. Do not share.';
const _due =
    'Your ICICI Bank Credit Card XX7102 statement is generated. Total due Rs 45,000.00, min due Rs 2,250 by 20-Nov-26.';
const _executed =
    'Rs 649.00 debited from A/c XX4012 on 16-Nov-26 towards Netflix UPI Autopay mandate. UPI Ref No 431712345678. Avl bal: Rs 45,000.00';
const _ccBill =
    'Rs 45,000.00 debited from A/c XX4012 on 14-Nov-26 towards ICICI Credit Card XX7102 bill payment.';
const _plainDebit =
    'HDFC Bank: Rs 500.00 debited from a/c **4012 on 13-11-26 to VPA swiggy@hdfcbank (UPI Ref No 431712345678). Avl bal: Rs 45,000.00';

void main() {
  setUpAll(setupTestDatabase);

  test('classifies each message by what it is about', () {
    final cases = {
      _predebit: MessageIntent.preDebit,
      _created: MessageIntent.mandateCreated,
      _cancelled: MessageIntent.mandateCancelled,
      _failed: MessageIntent.mandateFailed,
      _otp: MessageIntent.otp,
      _due: MessageIntent.statementDue,
      _executed: MessageIntent.transaction,
      _ccBill: MessageIntent.transaction,
      _plainDebit: MessageIntent.transaction,
    };
    for (final e in cases.entries) {
      expect(classifyMessage(e.key), e.value, reason: e.key);
    }
  });

  test('only real money movements parse as transactions', () {
    const parser = FinancialParser();
    RawNotification n(String b) => RawNotification(
      id: 'x',
      body: b,
      receivedAt: DateTime(2026, 11, 14),
      sender: 'VK-HDFCBK',
    );
    for (final text in [_predebit, _created, _cancelled, _failed, _otp, _due]) {
      expect(parser.parse(n(text)), isNull, reason: text);
    }
    expect(
      parser.parse(n(_ccBill))!.suggestedTransactionType,
      TransactionType.creditCardSettlement,
    );
    expect(parser.parse(n(_executed))!.amountMinorUnits, 64900);
  });

  test('notice details: payee, amount, date, umn', () {
    final n = parseMandateNotice(_predebit, MessageIntent.preDebit);
    expect(n.payee, 'Netflix');
    expect(n.amountMinorUnits, 64900);
    expect(n.date, DateTime(2026, 11, 16));
    expect(n.accountMask, '4012');
    final c = parseMandateNotice(_created, MessageIntent.mandateCreated);
    expect(c.payee, 'Spotify');
    expect(c.umn, 'abc123@okhdfc');
    expect(
      parseMandateNotice(_cancelled, MessageIntent.mandateCancelled).payee,
      'Netflix',
    );
  });

  group('ingestion end to end', () {
    late RiveroDatabase db;
    late IngestionService service;
    final now = DateTime(2026, 11, 14, 10);

    Future<IngestionResult> feed(String id, String body) =>
        service.processNotification(
          RawNotification(
            id: id,
            body: body,
            receivedAt: now,
            sender: 'VK-HDFCBK',
          ),
        );

    setUp(() async {
      db = RiveroDatabase.memory();
      service = IngestionService(database: db);
      await db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: const Value('a'),
          name: const Value('HDFC'),
          institution: const Value('HDFC'),
          accountMask: const Value('4012'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
    tearDown(() => db.close());

    Future<int> txnCount() async =>
        (await db.select(db.transactions).get()).length;

    test('pre-debit never becomes an expense but registers the mandate; the real debit rolls it forward', () async {
      await feed('1', _predebit);
      expect(await txnCount(), 0);
      var m = await db.mandatesDao.getAllMandates();
      expect(m, hasLength(1));
      expect(m.single.payee, 'Netflix');
      expect(m.single.nextExecutionDate, DateTime(2026, 11, 16));

      await feed('2', _executed);
      expect(await txnCount(), 1); // one real debit, not two
      m = await db.mandatesDao.getAllMandates();
      expect(m.single.nextExecutionDate, DateTime(2026, 12, 16));
    });

    test(
      'mandate created then revoked updates the Autopay list only',
      () async {
        await feed('1', _created);
        expect(
          (await db.mandatesDao.getAllMandates()).single.status,
          MandateStatus.active,
        );
        await feed(
          '2',
          'Your UPI mandate for Spotify Rs 199 has been cancelled.',
        );
        expect(
          (await db.mandatesDao.getAllMandates()).single.status,
          MandateStatus.cancelled,
        );
        expect(await txnCount(), 0);
      },
    );

    test('OTP, failed autopay and statement notices create nothing; OTP text is not stored', () async {
      await feed('1', _otp);
      await feed('2', _failed);
      await feed('3', _due);
      expect(await txnCount(), 0);
      final logs = await db.select(db.rawIngestionLogs).get();
      expect(logs.any((l) => l.rawPayload.contains('482913')), isFalse);
    });
  });
}
