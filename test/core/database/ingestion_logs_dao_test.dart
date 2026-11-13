import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;

  setUp(() {
    db = RiveroDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  group('IngestionLogsDao tests', () {
    test('insert log and filter quarantined items (EC-10)', () async {
      final now = DateTime.now();

      // Successfully parsed log
      await db.ingestionLogsDao.insertLog(
        RawIngestionLogsCompanion(
          id: const Value('log-01'),
          sourceChannel: const Value(IngestionChannel.notificationAndroid),
          senderHeader: const Value('AD-HDFCBK'),
          rawPayload: const Value(
            'Debited INR 500.00 from HDFC Bank A/C **4012',
          ),
          receivedAt: Value(now),
          parseStatus: const Value(ParseStatus.parsed),
          confidenceScore: const Value(0.95),
          createdAt: Value(now),
        ),
      );

      // Quarantined ambiguous log
      await db.ingestionLogsDao.insertLog(
        RawIngestionLogsCompanion(
          id: const Value('log-quarantine-01'),
          sourceChannel: const Value(IngestionChannel.notificationAndroid),
          senderHeader: const Value('UNKNOWN-MSG'),
          rawPayload: const Value('Important transaction alert: 500 ref 99401'),
          receivedAt: Value(now),
          parseStatus: const Value(ParseStatus.quarantined),
          confidenceScore: const Value(0.35),
          failureReason: const Value('Ambiguous amount direction'),
          createdAt: Value(now),
        ),
      );

      // Verify watchQuarantinedLogs only returns quarantined logs
      final quarantined = await db.ingestionLogsDao
          .watchQuarantinedLogs()
          .first;
      expect(quarantined.length, equals(1));
      expect(quarantined.first.id, equals('log-quarantine-01'));
      expect(
        quarantined.first.failureReason,
        equals('Ambiguous amount direction'),
      );

      // Resolve quarantine
      await db.ingestionLogsDao.updateParseStatus(
        'log-quarantine-01',
        ParseStatus.parsed,
      );
      final remainingQuarantined = await db.ingestionLogsDao
          .watchQuarantinedLogs()
          .first;
      expect(remainingQuarantined, isEmpty);
    });
  });
}
