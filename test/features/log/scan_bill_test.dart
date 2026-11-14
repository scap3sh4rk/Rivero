import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/import/bill_parser.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/storage/media_store.dart';
import 'package:rivero/features/log/scan_bill.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets('confirming a scanned bill saves it with the photo and date', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('rivero_scan_');
    addTearDown(() => dir.deleteSync(recursive: true));
    MediaStore.rootOverride = dir;
    addTearDown(() => MediaStore.rootOverride = null);
    final photo = File('${dir.path}/bill.jpg')..writeAsBytesSync([1, 2, 3]);

    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: BillConfirmSheet(
              draft: BillDraft(
                amountMinorUnits: 42000,
                merchant: 'Cafe Mocha',
                date: DateTime(2026, 11, 10),
                category: 'Food',
              ),
              imagePath: photo.path,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('420'), findsOneWidget); // pre-filled, editable

    await tester.tap(find.byKey(const ValueKey('bill-save')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
    }

    final all = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!;
    final t = all.firstWhere((t) => t.merchant == 'Cafe Mocha');
    expect(t.amountMinorUnits, -42000);
    expect(t.category, 'Food');
    expect(t.transactionTimestamp, DateTime(2026, 11, 10));
    expect(t.attachmentPath, isNotNull);
    expect(File(t.attachmentPath!).existsSync(), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
