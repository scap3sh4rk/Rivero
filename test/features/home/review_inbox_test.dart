import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/home/widgets/review_inbox.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets('Confirm and Ignore buttons resolve captured transactions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ReviewInbox())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('To review · 3'), findsOneWidget);

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm').first);
    await settle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ignore').first);
    await settle();

    final states = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!.map((t) => t.transactionState).toList();
    expect(states, contains(TransactionState.confirmed));
    expect(states, contains(TransactionState.ignored));
    expect(find.text('To review · 1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets("a message Rivero couldn't read is shown, then dismissed", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await IngestionService(database: db).processNotification(
      RawNotification(
        id: 'odd',
        body: 'Your SBI account was debited for a UPI payment. See YONO.',
        sender: 'VM-SBIUPI',
        receivedAt: DateTime.now(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ReviewInbox())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining("couldn't be read"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('unreadable-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('YONO'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dismiss-odd')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Nothing left to check'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
