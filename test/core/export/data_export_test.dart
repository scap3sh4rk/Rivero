import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/export/data_export.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  test('rupees are exact decimals from paise', () {
    expect(DataExport.rupees(12345), '123.45');
    expect(DataExport.rupees(5), '0.05');
    expect(DataExport.rupees(-100), '-1.00');
    expect(DataExport.rupees(0), '0.00');
  });

  test('CSV escapes commas, quotes, newlines and formula injection', () {
    final s = DataExport.csv(
      const ExportSheet(
        'T',
        ['a', 'b'],
        [
          ['Swiggy, Bangalore', 'say "hi"'],
          ['=HYPERLINK("x")', '-12.50'],
          ['line\nbreak', 'plain'],
        ],
      ),
    );
    final lines = s.split('\n');
    expect(lines[1], '"Swiggy, Bangalore","say ""hi"""');
    // A formula is defused; a negative number is left alone.
    expect(lines[2], '"\'=HYPERLINK(""x"")",-12.50');
    expect(s, contains('"line\nbreak",plain'));
  });

  test('the workbook and the CSV zip contain every table', () async {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();
    final export = DataExport(db);

    final xlsx = ZipDecoder().decodeBytes(await export.xlsx());
    final names = xlsx.files.map((f) => f.name).toSet();
    expect(names, containsAll(['xl/workbook.xml', 'xl/worksheets/sheet1.xml']));
    final wb = utf8.decode(xlsx.findFile('xl/workbook.xml')!.content);
    for (final s in ['Transactions', 'Accounts', 'Plan', 'Owed', 'Autopay']) {
      expect(wb, contains('name="$s"'));
    }
    final sheet1 = utf8.decode(
      xlsx.findFile('xl/worksheets/sheet1.xml')!.content,
    );
    expect(sheet1, contains('Zomato'));

    final zip = ZipDecoder().decodeBytes(await export.csvZip());
    expect(
      zip.files.map((f) => f.name),
      containsAll(['transactions.csv', 'accounts.csv', 'plan.csv']),
    );
    final accounts = utf8.decode(zip.findFile('accounts.csv')!.content);
    expect(accounts, contains('Primary HDFC Salary'));
  });
}
