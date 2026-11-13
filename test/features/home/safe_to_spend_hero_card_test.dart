import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/features/home/widgets/safe_to_spend_hero_card.dart';

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

  testWidgets('SafeToSpendHeroCard renders liquidity, pace and reliability', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: SafeToSpendHeroCard())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SAFE TO SPEND PER DAY'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('SafeToSpendHeroCard masks amount when privacy mode enabled', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        privacyModeProvider.overrideWith((ref) => true),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SafeToSpendHeroCard())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('••••••••'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test(
    'pill stays neutral while fine, warms when low, red only for deficit',
    () {
      expect(SafeToSpendHeroCard.toneFor(0.9), RiveroColors.textSecondary);
      expect(SafeToSpendHeroCard.toneFor(0.4), RiveroColors.textSecondary);
      expect(SafeToSpendHeroCard.toneFor(0.15), RiveroColors.warning);
      expect(SafeToSpendHeroCard.toneFor(0), RiveroColors.danger);
      expect(
        SafeToSpendHeroCard.toneFor(0.9, deficit: true),
        RiveroColors.danger,
      );
    },
  );
}
