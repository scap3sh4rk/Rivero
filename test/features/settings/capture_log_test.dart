import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/settings/screens/capture_log_screen.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets('recent captures show what happened to each notification', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    final now = DateTime.now();
    Future<void> log(String id, String body, ParseStatus s, [String? why]) =>
        db.ingestionLogsDao.insertLog(
          RawIngestionLogsCompanion.insert(
            id: id,
            sourceChannel: IngestionChannel.notificationAndroid,
            rawPayload: body,
            receivedAt: now,
            parseStatus: s,
            createdAt: now,
            senderHeader: const Value('com.phonepe.app'),
            failureReason: Value(why),
          ),
        );
    await log('a', 'Paid ₹500 to Rahul', ParseStatus.parsed);
    await log(
      'b',
      '[OTP message not stored]',
      ParseStatus.ignored,
      'Not a transaction: otp',
    );
    await log(
      'c',
      'weird bank text',
      ParseStatus.failed,
      'No recognizable financial entities found',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CaptureLogScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Recorded'), findsOneWidget);
    expect(find.text('Ignored: one-time password'), findsOneWidget);
    expect(find.text("Couldn't read this message"), findsOneWidget);
    expect(find.textContaining('PhonePe'), findsWidgets); // friendly name

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  test('the chosen UPI app is remembered and trusted by the parser', () async {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    final c = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    await c.read(settingsSyncProvider).load();
    c.read(settingsSyncProvider).listen();
    expect(c.read(primaryUpiProvider), isNull);
    c.read(primaryUpiProvider.notifier).state = 'com.example.newupi';
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      await db.settingsDao.get(SettingKeys.primaryUpi),
      'com.example.newupi',
    );
    expect(
      c
          .read(financialParserProvider)
          .dltValidator
          .isFinancialSender(packageName: 'com.example.newupi'),
      isTrue,
    );
  });
}
