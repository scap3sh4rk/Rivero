import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';

import '../../test_helper.dart';

void main() {
  setupTestDatabase();

  group('IngestionService', () {
    late RiveroDatabase db;
    late IngestionService service;
    final now = DateTime(2026, 11, 13, 16);

    setUp(() {
      db = RiveroDatabase.memory();
      service = IngestionService(database: db);
    });

    tearDown(() async {
      await db.close();
    });

    test('an SBI-style payment to a friend lands in the review inbox', () async {
      final result = await service.processNotification(
        RawNotification(
          id: 'sms-sbi-1',
          title: 'Rahul',
          sender: 'VM-SBIUPI',
          packageName: 'com.samsung.android.messaging',
          body:
              'Dear UPI user A/C X1234 debited by 500.0 on date 13Nov26 trf to '
              'Rahul Kumar Refno 612345678901 If not u? call 1800111109. -SBI',
          receivedAt: now,
        ),
      );
      expect(result.status, ParseStatus.parsed);
      final txns = await db.transactionsDao.watchRecentTransactions().first;
      expect(txns.single.amountMinorUnits, -50000);
    });

    test('ingests and confirms standard bank SMS into ledger', () async {
      final notif = RawNotification(
        id: 'sms-hdfc-1',
        sender: 'VK-HDFCBK',
        body: 'HDFC Bank: Rs 500.00 debited from a/c **1234 on 13-11-26 to VPA swiggy@hdfcbank (UPI Ref No 431712345678). Avl bal: Rs 45,000.00',
        receivedAt: now,
      );

      final result = await service.processNotification(notif);

      expect(result.status, ParseStatus.parsed);
      expect(result.isDuplicate, isFalse);
      expect(result.persistedTransactionId, isNotNull);

      // Verify raw audit log was written
      final logs = await db.ingestionLogsDao.watchRecentLogs().first;
      expect(logs.length, 1);
      expect(logs.first.id, 'sms-hdfc-1');
      expect(logs.first.parseStatus, ParseStatus.parsed);

      // Verify ledger transaction was created
      final txns = await db.transactionsDao.watchRecentTransactions().first;
      expect(txns.length, 1);
      expect(txns.first.id, result.persistedTransactionId);
      expect(txns.first.amountMinorUnits, -50000); // -₹500.00 (debit)
      expect(txns.first.merchant, 'swiggy');
      expect(txns.first.referenceNumber, '431712345678');
      expect(txns.first.transactionState, TransactionState.confirmed);
    });

    test(
      'deduplicates subsequent UPI app push notification for same event',
      () async {
        // 1. Bank SMS arrives first
        final bankSms = RawNotification(
          id: 'event-1',
          sender: 'VK-HDFCBK',
          body: 'HDFC Bank: Rs 450.00 debited from a/c **1234 on 13-11-26 to VPA swiggy@hdfcbank (UPI Ref No 431712345678). Avl bal: Rs 45,000.00',
          receivedAt: now,
        );
        final firstResult = await service.processNotification(bankSms);
        expect(firstResult.isDuplicate, isFalse);

        // 2. UPI app push notification arrives 15s later
        final appPush = RawNotification(
          id: 'event-2',
          packageName: 'com.phonepe.app',
          title: 'Payment Successful',
          body: 'Payment of ₹450 to Swiggy was successful.',
          receivedAt: now.add(const Duration(seconds: 15)),
        );
        final secondResult = await service.processNotification(appPush);

        // Must be flagged as duplicate and merged
        expect(secondResult.isDuplicate, isTrue);
        expect(
          secondResult.persistedTransactionId,
          firstResult.persistedTransactionId,
        );

        // Verify ledger still has only 1 transaction (no double counting!)
        final txns = await db.transactionsDao.watchRecentTransactions().first;
        expect(txns.length, 1);

        // But raw audit logs retain BOTH raw events for auditability
        final logs = await db.ingestionLogsDao.watchRecentLogs().first;
        expect(logs.length, 2);
      },
    );

    test(
      'logs failed status for non-financial spam without touching ledger',
      () async {
        final spam = RawNotification(
          id: 'spam-1',
          sender: 'VM-OFFERS',
          body: 'Flat 50% discount on clothing today! Visit store.',
          receivedAt: now,
        );

        final result = await service.processNotification(spam);

        expect(result.status, ParseStatus.failed);
        expect(result.persistedTransactionId, isNull);

        final txns = await db.transactionsDao.watchRecentTransactions().first;
        expect(txns, isEmpty);

        final logs = await db.ingestionLogsDao.watchRecentLogs().first;
        expect(logs.length, 1);
        expect(logs.first.parseStatus, ParseStatus.failed);
      },
    );
  });
}
