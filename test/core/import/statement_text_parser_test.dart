import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/import/statement_text_parser.dart';

void main() {
  test('bank statement: direction from the running balance', () {
    final rows = parseStatementText([
      'Date Narration Chq./Ref.No. Value Dt Withdrawal Amt. Deposit Amt. Closing Balance',
      'Opening Balance 50,000.00',
      '01/11/26 UPI-SWIGGY-swiggy@icici-431712345678 0000431712345678 01/11/26 450.00 49,550.00',
      '02/11/26 NEFT CR-ACME CORP SALARY N306261234 02/11/26 85,000.00 1,34,550.00',
      '03/11/26 ATM WDL 003 03/11/26 2,000.00 1,32,550.00',
      'Closing Balance 1,32,550.00',
    ]);
    expect(rows.map((r) => r.amountMinorUnits), [-45000, 8500000, -200000]);
    expect(rows[1].date, DateTime(2026, 11, 2));
    expect(rows.first.description, startsWith('UPI-SWIGGY'));
  });

  test('Dr/Cr marks when there is no balance column', () {
    final rows = parseStatementText([
      '05-Nov-2026 POS AMAZON 1,299.00 Dr',
      '06-Nov-2026 REFUND AMAZON 299.00 Cr',
    ]);
    expect(rows.map((r) => r.amountMinorUnits), [-129900, 29900]);
    expect(rows[1].date, DateTime(2026, 11, 6));
  });

  test('Google Pay and PhonePe statements: words decide', () {
    final gpay = parseStatementText([
      '01 Nov, 2026 Paid to Swiggy UPI Transaction ID: 431712345678 ₹450',
      '02 Nov, 2026 Received from Ravi Kumar ₹1,200',
    ]);
    expect(gpay.map((r) => r.amountMinorUnits), [-45000, 120000]);
    expect(gpay.first.description, contains('Paid to Swiggy'));

    final phonepe = parseStatementText([
      'Nov 03, 2026 Paid to Zomato DEBIT ₹320',
      'Nov 04, 2026 Received from Meera CREDIT ₹500',
    ]);
    expect(phonepe.map((r) => r.amountMinorUnits), [-32000, 50000]);
    expect(phonepe.first.date, DateTime(2026, 11, 3));
  });

  test('headers, totals and lines without a date or amount are skipped', () {
    expect(
      parseStatementText([
        'Account statement for XX4012',
        'Total 1,234.00',
        '31/02/2026 not a real date 100.00 Dr',
        '07/11/2026 reference 431712345678 only',
      ]),
      isEmpty,
    );
  });
}
