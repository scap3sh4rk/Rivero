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
}
