import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/settings/screens/settings_screen.dart';

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

  testWidgets(
    'SettingsScreen displays paycycle, account types, credit score rules, and privacy mode',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('PAYCYCLE CONFIGURATION'), findsOneWidget);
      expect(find.text('Salary Credit Day'), findsOneWidget);
      expect(find.textContaining('CUSTOM ACCOUNT TYPES'), findsOneWidget);
      expect(find.text('CREDIT SCORE MONITORING'), findsOneWidget);
      expect(find.text('PRIVACY & SECURITY'), findsOneWidget);
      expect(find.text('DATA CONTROLS'), findsOneWidget);

      // Verify credit rules text
      expect(find.textContaining('<= 10% Utilization'), findsOneWidget);
      expect(find.textContaining('> 30% Utilization'), findsOneWidget);

      // Verify privacy mode toggle switch
      final privacySwitch = find.byType(Switch);
      expect(privacySwitch, findsOneWidget);
      await tester.tap(privacySwitch);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}
