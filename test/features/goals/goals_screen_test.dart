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

  testWidgets('a goal is created, edited, and deleted only after asking', (
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
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    await settle();
    expect(find.textContaining('No goals yet'), findsOneWidget);

    // New goal: ₹50,000 with ₹20,000 cash at home counting towards it.
    await tester.tap(find.byTooltip('Add goal'));
    await settle();
    await tester.enterText(find.byKey(const ValueKey('goal-name')), 'Goa');
    await tester.enterText(find.byKey(const ValueKey('goal-target')), '50000');
    await tester.tap(find.byKey(const ValueKey('goal-add-source')));
    await settle();
    await tester.tap(find.byKey(const ValueKey('source-asset')));
    await settle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-label')),
      'Cash at home',
    );
    await tester.enterText(find.byKey(const ValueKey('asset-value')), '20000');
    await tester.tap(find.byKey(const ValueKey('asset-save')));
    await settle();
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await settle();

    final saved = (await tester.runAsync(() => Goals(db).load()))!.single;
    expect(saved.targetMinorUnits, 5000000);
    expect(saved.sources.single.valueMinorUnits, 2000000);
    expect(find.text('Goa'), findsOneWidget);
    expect(find.textContaining('₹20,000.00 of ₹50,000'), findsOneWidget);
    // No one-tap delete on the card.
    expect(find.byTooltip('Remove goal'), findsNothing);

    // Edit: rename it.
    await tester.tap(find.text('Goa'));
    await settle();
    expect(find.text('Edit goal'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('goal-name')), 'Goa trip');
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await settle();
    expect(find.text('Goa trip'), findsOneWidget);

    // Delete asks first; "Keep it" keeps it.
    await tester.tap(find.text('Goa trip'));
    await settle();
    await tester.tap(find.byKey(const ValueKey('goal-delete')));
    await settle();
    await tester.tap(find.text('Keep it'));
    await settle();
    expect(await tester.runAsync(() => Goals(db).load()), hasLength(1));
    // Confirm deletes it, and Undo brings it back.
    await tester.tap(find.byKey(const ValueKey('goal-delete')));
    await settle();
    await tester.tap(find.byKey(const ValueKey('goal-delete-confirm')));
    await settle();
    expect(await tester.runAsync(() => Goals(db).load()), isEmpty);
    await tester.tap(find.text('Undo'));
    await settle();
    expect(
      (await tester.runAsync(() => Goals(db).load()))!.single.name,
      'Goa trip',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
