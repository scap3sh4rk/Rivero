import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/main/main_screen.dart';
import 'package:rivero/features/transactions/screens/transactions_screen.dart';

import '../../test_helper.dart';

Finder nav(String label) => find.byKey(ValueKey('nav-$label'));

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

  testWidgets('MainScreen switches between pages and opens settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: MainScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('SAFE TO SPEND PER DAY'), findsOneWidget);

    // Dragging along the bottom bar scrubs tabs: Home -> two to the right.
    await tester.drag(
      find.byKey(const ValueKey('nav-bar')),
      const Offset(120, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainScreen)),
    );
    expect(container.read(selectedNavIndexProvider), 4);

    Future<void> open(String tab) async {
      await tester.tap(nav(tab));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await open('Accounts');
    expect(find.text('Bank & cash'), findsOneWidget);

    await open('Log');
    expect(find.byKey(const ValueKey('key-5')), findsOneWidget);

    await open('Activity');
    expect(find.text('Activity'), findsWidgets);

    await open('Owed');
    expect(find.text('Owed to you'), findsOneWidget);

    // Home shortcut cards jump to their pages.
    await open('Home');
    await tester.tap(find.byKey(const ValueKey('home-owed')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Owed to you'), findsOneWidget);
    await open('Home');
    await tester.tap(find.byKey(const ValueKey('home-plan')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('MONTHLY SALARY'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Settings is reached from the profile button
    await tester.tap(find.byTooltip('Profile & Settings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('section-money')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('back clears Activity search, then returns Home', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: MainScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final c = ProviderScope.containerOf(
      tester.element(find.byType(MainScreen)),
    );

    await tester.tap(nav('Activity'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField).first, 'Zomato');
    await tester.pump();
    expect(find.byKey(const ValueKey('clear-search')), findsOneWidget);

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await back();
    expect(c.read(activityQueryProvider), isEmpty);
    expect(c.read(selectedNavIndexProvider), 4); // still on Activity

    await back();
    expect(c.read(selectedNavIndexProvider), 2); // Home

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
