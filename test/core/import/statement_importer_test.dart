import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/engine/spending_summary.dart';
import 'package:rivero/core/import/statement_importer.dart';
import 'package:rivero/core/import/statement_parser.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  test('imports history once, without touching the balance', () async {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    final now = DateTime(2026, 11, 14);
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('a'),
        name: const Value('HDFC'),
        institution: const Value('HDFC'),
        accountMask: const Value('4012'),
        balanceMinorUnits: const Value(5000000),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    final rows = [
      StatementRow(
        date: DateTime(2026, 10, 2),
        description: 'SWIGGY',
        amountMinorUnits: -45000,
      ),
      StatementRow(
        date: DateTime(2026, 10, 3),
        description: 'SALARY',
        amountMinorUnits: 9000000,
      ),
    ];
    final first = await StatementImporter(db).importRows('a', rows);
    expect(first, (added: 2, skipped: 0));
    final again = await StatementImporter(db).importRows('a', rows);
    expect(again, (added: 0, skipped: 2));

    expect(
      (await db.accountsDao.getPhysicalAccountById('a'))!.balanceMinorUnits,
      5000000,
    );
    // History counts in spending reports.
    final s = SpendingSummary.of(
      await db.select(db.transactions).get(),
      start: DateTime(2026, 10),
      end: DateTime(2026, 10, 31),
    );
    expect(s.total, 45000);
  });
}
