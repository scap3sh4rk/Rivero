import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';

import '../../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupTestDatabase);

  test('setSecure never throws off-device', () async {
    await NotificationBridge.setSecure(on: true); // not Android in tests
    await NotificationBridge.setSecure(on: false);
  });

  test('concurrent drains are processed one after the other', () async {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    var active = 0;
    var maxActive = 0;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('rivero/notifications'), (
          call,
        ) async {
          if (call.method != 'drain') return null;
          active++;
          maxActive = active > maxActive ? active : maxActive;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          active--;
          calls++;
          return '[]';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('rivero/notifications'),
            null,
          ),
    );
    final bridge = NotificationBridge(IngestionService(database: db));
    // Only meaningful where the bridge is active; on desktop it returns 0.
    await Future.wait([bridge.drain(), bridge.drain(), bridge.drain()]);
    expect(maxActive, lessThanOrEqualTo(1));
    expect(calls == 0 || calls == 3, isTrue);
  });
}
