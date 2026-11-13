import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';

import '../../test_helper.dart';

void main() {
  setupTestDatabase();
  test(
    'ingestJson feeds queued notifications into the ingestion log',
    () async {
      final db = RiveroDatabase.memory();
      addTearDown(db.close);
      final bridge = NotificationBridge(IngestionService(database: db));
      final n = await bridge.ingestJson(
        jsonEncode([
          {
            'id': 'a:1:1700000000000',
            'package': 'com.phonepe.app',
            'title': 'PhonePe',
            'body': 'Rs 250.00 debited from A/c XX4012 to Chai Stall',
            'time': 1700000000000,
          },
        ]),
      );
      expect(n, 1);
      expect(await db.select(db.rawIngestionLogs).get(), hasLength(1));
    },
  );

  test('the in-app test notification is captured as a Rs 1 expense', () async {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    final bridge = NotificationBridge(IngestionService(database: db));
    final now = DateTime(2026, 11, 14, 9, 30);
    final body = NotificationBridge.sampleMessage(mask: '4012', now: now);
    expect(body.toLowerCase(), isNot(contains('bal'))); // never touches balance
    await bridge.ingestJson(
      jsonEncode([
        {
          'id': 'dev.scap3sh4rk.rivero:test:1',
          'package': 'dev.scap3sh4rk.rivero',
          'title': 'Bank alert (test)',
          'body': body,
          'time': now.millisecondsSinceEpoch,
        },
      ]),
    );
    final txns = await db.select(db.transactions).get();
    expect(txns, hasLength(1));
    expect(txns.single.amountMinorUnits, -100);
  });
}
