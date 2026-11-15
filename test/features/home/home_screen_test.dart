import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/widgets/brand_wordmark.dart';
import 'package:rivero/features/home/screens/home_screen.dart';
import 'package:rivero/features/home/widgets/simulate_sms_sheet.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;

  setUp(() async {
    db = RiveroDatabase.memory();
    await DatabaseSeeder(db).seedIfEmpty();
    // Backed up recently: no backup reminder on Home.
    await db.settingsDao.set(
      SettingKeys.lastBackupAt,
      DateTime.now().toIso8601String(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'HomeScreen renders all primary components and opens simulation',
    (tester) async {
      // A phone-sized screen, so the list below the hero card is built.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Rivero'), findsOneWidget);
      expect(find.text('SAFE TO SPEND PER DAY'), findsOneWidget);
      expect(find.text('To review · 3'), findsOneWidget);

      // Tap simulate notification button in AppBar
      final simulateButton = find.byTooltip('Simulate Notification');
      expect(simulateButton, findsOneWidget);

      await tester.tap(simulateButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify simulate sheet appears
      expect(find.text('Simulate Bank Notification'), findsOneWidget);

      // Dismiss sheet
      final closeButton = find.descendant(
        of: find.byType(SimulateSmsSheet),
        matching: find.byIcon(Icons.close),
      );
      await tester.tap(closeButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets('the wordmark animates in once, then stays', (tester) async {
    BrandWordmark.played = false;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrandWordmark())),
    );
    final w0 = tester.getSize(find.byType(ClipRect).last).width;
    await tester.pump(const Duration(milliseconds: 300));
    final clip = tester.widget<ClipRect>(find.byType(ClipRect).last);
    expect(clip.clipper, isNotNull);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Rivero'), findsOneWidget);
    expect(w0, greaterThan(0));

    // A second visit shows it fully, without replaying.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrandWordmark())),
    );
    expect(find.text('Rivero'), findsOneWidget);
    expect(BrandWordmark.played, isTrue);
  });
}
