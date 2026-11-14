import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/import/bill_parser.dart';
import 'package:rivero/core/import/statement_parser.dart';

void main() {
  test('bill: total line wins over items and subtotal', () {
    const text = '''
Cafe Mocha
GSTIN 29ABCDE1234F1Z5
Date: 14/11/2026
Cappuccino 1 x 180.00
Sandwich 1 x 220.00
Sub Total 400.00
CGST 2.5% 10.00
SGST 2.5% 10.00
Grand Total
₹ 420.00
Thank you!''';
    final b = parseBillText(text);
    expect(b.amountMinorUnits, 42000);
    expect(b.merchant, 'Cafe Mocha');
    expect(b.date, DateTime(2026, 11, 14));
    expect(b.category, 'Food');
  });

  test('bill without a total line falls back to the largest figure', () {
    final b = parseBillText(
      'Apollo Pharmacy\nParacetamol 35\nVitamin C 1,250.50',
    );
    expect(b.amountMinorUnits, 125050);
    expect(b.category, 'Health');
  });

  test('csv splitting keeps quoted commas together', () {
    expect(splitCsvLine('a,"b, c",d'), ['a', 'b, c', 'd']);
    expect(splitCsvLine('"say ""hi""",2'), ['say "hi"', '2']);
  });

  test('statement with separate debit/credit columns (HDFC-style)', () {
    const csv = '''
HDFC BANK Ltd. Statement
Date,Narration,Chq./Ref.No.,Value Dt,Withdrawal Amt.,Deposit Amt.,Closing Balance
01/11/26,UPI-SWIGGY-swiggy@hdfc,431,01/11/26,"1,250.00",,"48,750.00"
01/11/26,SALARY ACME LTD,NEFT,01/11/26,,"90,000.00","1,38,750.00"
,Opening Balance,,,,,
''';
    final rows = parseStatementCsv(csv);
    expect(rows, hasLength(2));
    expect(rows[0].amountMinorUnits, -125000);
    expect(rows[0].date, DateTime(2026, 11));
    expect(rows[1].amountMinorUnits, 9000000);
    expect(rows[1].description, 'SALARY ACME LTD');
  });

  test('statement with a single signed amount column', () {
    const csv =
        'Txn Date,Description,Amount\n2026-11-03,Uber trip,-320.50\n2026-11-04,Refund,99 Cr\n2026-11-05,Rent,25000 Dr';
    final rows = parseStatementCsv(csv);
    expect(rows.map((r) => r.amountMinorUnits), [-32050, 9900, -2500000]);
  });

  test('unrecognised files yield nothing instead of garbage', () {
    expect(parseStatementCsv('hello,world\n1,2'), isEmpty);
  });
}
