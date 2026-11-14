import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('Settings rows open pickers and sub-pages without crowding', (
    tester,
  ) async {
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
    expect(find.text('Pay day'), findsOneWidget);
    expect(find.text('Account types'), findsOneWidget);
    expect(find.text('Autopay'), findsOneWidget);
    expect(find.text('Load demo data'), findsOneWidget);
    // The account types list no longer crowds this page.
    expect(find.text('Fixed Deposit'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    await tester.tap(find.byKey(const ValueKey('privacy-switch')));
    await tester.pump();
    expect(container.read(privacyModeProvider), isTrue);

    // Pay day picker
    await tester.tap(find.text('Pay day'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('25'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(userSalaryDayProvider), 25);

    // Account types open on their own page
    await tester.tap(find.text('Account types'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Fixed Deposit'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('developer card shows the name and opens repo and issues', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch') {
          opened.add((call.arguments as Map)['url'] as String);
          return true;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('developer-card')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Parthiv Kumar Nikku'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('link-repo')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('link-issues')));
    await tester.pump();
    expect(opened, [
      'https://github.com/scap3sh4rk/Rivero',
      'https://github.com/scap3sh4rk/Rivero/issues',
    ]);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
