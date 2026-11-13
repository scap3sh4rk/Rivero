import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/home/widgets/simulate_sms_sheet.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;

  setUp(() async {
    db = RiveroDatabase.memory();
    await DatabaseSeeder(db).seedIfEmpty();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('SimulateSmsSheet renders presets and ingests notification', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: SimulateSmsSheet())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Simulate Bank Notification'), findsOneWidget);
    expect(find.text('HDFC UPI Debit (Starbucks)'), findsOneWidget);
    expect(find.text('Ingest & Process Notification'), findsOneWidget);

    // Tap ingest button
    final ingestButton = find.widgetWithText(
      ElevatedButton,
      'Ingest & Process Notification',
    );
    expect(ingestButton, findsOneWidget);

    await tester.tap(ingestButton);
    await tester.pump();
    // Real DB work runs outside the fake clock; give it time to finish.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    // Pump past the 1.2s delayed dismiss timer
    await tester.pump(const Duration(seconds: 2));

    // Verify notification was ingested into database
    final transactions = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!;
    expect(transactions.any((t) => t.merchant.contains('STARBUCKS')), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
