import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/main.dart';

import 'test_helper.dart';

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

  testWidgets('RiveroApp renders interactive home and toggles privacy mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const RiveroApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Rivero'), findsOneWidget);
    expect(find.text('SAFE TO SPEND'), findsOneWidget);
    expect(find.text('INBOX TRIAGE'), findsOneWidget);

    // Toggle privacy mode
    final privacyButton = find.byTooltip('Toggle Privacy Mode');
    expect(privacyButton, findsOneWidget);

    await tester.tap(privacyButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify balances masked
    expect(find.text('••••••••'), findsWidgets);

    // Tear down widget tree cleanly before test ends to flush drift query timers
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
