import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/home/widgets/transaction_swiper_section.dart';

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
    'TransactionSwiperSection renders review cards and triage actions',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: TransactionSwiperSection()),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('INBOX TRIAGE'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // 3 pending review cards
      expect(find.text('Zomato'), findsOneWidget);
      expect(find.text('Confirm'), findsWidgets);
      expect(find.text('Ignore'), findsWidgets);

      // Tap confirm on the top card
      final confirmButtons = find.widgetWithText(ElevatedButton, 'Confirm');
      expect(confirmButtons, findsWidgets);

      await tester.tap(confirmButtons.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify first transaction state is now confirmed in database
      final txn1 = await db.transactionsDao.getTransactionById('txn-review-1');
      expect(txn1?.transactionState, equals(TransactionState.confirmed));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets('TransactionSwiperSection shows Inbox Zero when list is empty', (
    tester,
  ) async {
    final emptyDb = RiveroDatabase.memory();
    addTearDown(emptyDb.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(emptyDb)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: TransactionSwiperSection()),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Inbox Zero'), findsOneWidget);
    expect(
      find.text('All caught up! No incoming transactions pending review.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
