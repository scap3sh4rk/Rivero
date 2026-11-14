import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/goals/goals.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/goals/goals_screen.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets('add a goal: it is saved and shown with its progress', (
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
        child: const MaterialApp(home: GoalsScreen()),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await settle();
    expect(find.textContaining('No goals yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Add goal'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('goal-name')), 'Goa');
    await tester.enterText(find.byKey(const ValueKey('goal-target')), '50000');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await settle();
    final saved = (await tester.runAsync(() => Goals(db).load()))!;
    expect(saved.single.targetMinorUnits, 5000000);
    expect(find.text('Goa'), findsOneWidget);
    expect(find.textContaining('of ₹50,000'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
