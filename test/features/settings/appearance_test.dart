import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/look.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/features/accounts/screens/accounts_screen.dart';
import 'package:rivero/features/settings/screens/appearance_screen.dart';
import 'package:rivero/main.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  setUp(() async {
    db = RiveroDatabase.memory();
    await DatabaseSeeder(db).seedIfEmpty();
  });
  tearDown(() async {
    RiveroLook.current = const Look();
    await db.close();
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('Look', () {
    test('saves and loads every choice', () {
      const l = Look(
        accent: 3,
        darkBackground: DarkBackground.midnight,
        lightBackground: LightBackground.white,
        weight: 2,
        textScale: 1.2,
        corners: 20,
        bankCards: CardSize.compact,
        creditCards: CardSize.large,
        heroScale: 0.8,
        borders: false,
      );
      expect(Look.fromJson(l.toJson()), l);
    });

    test('bad or missing data falls back to the original look', () {
      expect(Look.fromJson(null), const Look());
      expect(Look.fromJson('not json'), const Look());
      expect(
        Look.fromJson('{"accent": 99, "textScale": 9, "bankCards": "huge"}'),
        const Look(accent: 8, textScale: Look.maxText),
      );
    });

    test('every font is bundled at every weight step', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final f in RiveroFonts.families) {
        for (final w in [-1, 1, 2]) {
          RiveroLook.current = Look(weight: w);
          RiveroFonts.current = f;
          expect(pubspec, contains('- family: ${RiveroFonts.active}\n'));
        }
      }
      RiveroFonts.current = RiveroFonts.families.first;
    });

    test('tokens follow it', () {
      RiveroLook.current = const Look(accent: 4, weight: 1, heroScale: 0.75);
      expect(RiveroColors.accent, AccentChoice.all[4].dark);
      // Weight changes the whole font (every weight a step heavier), so
      // text with a fixed weight follows too.
      expect(RiveroTypography.bodyLarge.fontFamily, 'Urbanist Bold');
      expect(
        RiveroTheme.build(light: false).textTheme.bodyLarge?.fontFamily,
        'Urbanist Bold',
      );
      expect(RiveroTypography.financialHero.fontSize, 39);
      // The mono font keeps its weights.
      expect(RiveroTypography.monoMedium.fontWeight, FontWeight.w400);
    });
  });

  testWidgets('changing the look keeps Appearance open and restyles the app', (
    tester,
  ) async {
    phone(tester);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const RiveroApp()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(builder: (_) => const AppearanceScreen()),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AppearanceScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('accent-Green')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AppearanceScreen), findsOneWidget); // still here
    expect(RiveroColors.accent, AccentChoice.all[4].dark);
    expect(container.read(lookProvider).accent, 4);

    await tester.tap(find.text('Charcoal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(RiveroColors.background, const Color(0xFF121214));
    final scaffold = tester.widget<Scaffold>(
      find
          .descendant(
            of: find.byType(AppearanceScreen),
            matching: find.byType(Scaffold),
          )
          .first,
    );
    expect(scaffold.backgroundColor, const Color(0xFF121214));

    // Text size reaches every screen through the app's MediaQuery.
    container.read(lookProvider.notifier).state = container
        .read(lookProvider)
        .copyWith(textScale: 1.2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final ctx = tester.element(find.byType(AppearanceScreen));
    expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(12, 0.01));

    // The button is far down the list: press it directly.
    tester
        .widget<OutlinedButton>(find.byKey(const ValueKey('look-reset')))
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(lookProvider), const Look());

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  for (final size in CardSize.values) {
    testWidgets('bank and credit cards draw at ${size.name} size', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            lookProvider.overrideWith(
              (ref) => Look(bankCards: size, creditCards: size),
            ),
          ],
          child: const MaterialApp(home: AccountsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull); // no overflow
      expect(find.byKey(const ValueKey('balance-acc-salary')), findsOneWidget);
      // Only large bank cards spell out "Balance" above the amount.
      expect(
        find.text('Balance'),
        size == CardSize.large ? findsWidgets : findsNothing,
      );
      // The billing cycle is left out of compact credit cards.
      expect(
        find.byKey(const ValueKey('cycle-acc-cc')),
        size == CardSize.compact ? findsNothing : findsOneWidget,
      );
      expect(find.byKey(const ValueKey('afford-acc-cc')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  }
}
