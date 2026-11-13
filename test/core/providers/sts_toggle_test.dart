import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  test(
    'card reservation toggle changes Safe-to-Spend by the card liability',
    () async {
      final db = RiveroDatabase.memory();
      addTearDown(db.close);
      await DatabaseSeeder(db).seedIfEmpty();
      final c = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(c.dispose);
      c
        ..listen(liveSafeToSpendResultProvider, (_, _) {})
        ..listen(activeMandatesProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final on = c.read(liveSafeToSpendResultProvider).value!;
      c.read(reserveCreditCardsProvider.notifier).state = false;
      final off = c.read(liveSafeToSpendResultProvider).value!;

      expect(on.unsettledCreditCardLiability, 1425000);
      expect(off.unsettledCreditCardLiability, 0);
      expect(off.effectiveSafeToSpend - on.effectiveSafeToSpend, 1425000);
    },
  );

  test('carried-over money counts toward Safe-to-Spend', () async {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();
    final c = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    c
      ..listen(liveSafeToSpendResultProvider, (_, _) {})
      ..listen(activeMandatesProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final before = c.read(liveSafeToSpendResultProvider).value!;

    await (db.update(
      db.allocationBuckets,
    )..where((b) => b.id.equals('bucket-expense'))).write(
      const AllocationBucketsCompanion(carryOverMinorUnits: Value(500000)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final after = c.read(liveSafeToSpendResultProvider).value!;
    expect(after.effectiveSafeToSpend - before.effectiveSafeToSpend, 500000);
  });
}
