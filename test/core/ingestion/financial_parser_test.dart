import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ingestion/parser/financial_parser.dart';

void main() {
  group('FinancialParser', () {
    const parser = FinancialParser();
    final now = DateTime(2026, 11, 13, 14, 30);

    test('parses HDFC Bank UPI debit correctly', () {
      final notif = RawNotification(
        id: 'n1',
        sender: 'VK-HDFCBK',
        body: 'HDFC Bank: Rs 450.00 debited from a/c **1234 on 13-11-26 to VPA swiggy@hdfcbank (UPI Ref No 431712345678). Avl bal: Rs 45,210.50',
        receivedAt: now,
      );

      final parsed = parser.parse(notif);
      expect(parsed, isNotNull);
      expect(parsed!.amountMinorUnits, 45000); // ₹450.00
      expect(parsed.isDebit, isTrue);
      expect(parsed.accountMask, '1234');
      expect(parsed.merchant, 'swiggy');
      expect(parsed.referenceNumber, '431712345678');
      expect(parsed.balanceMinorUnits, 4521050); // ₹45,210.50
      expect(parsed.suggestedTransactionType, TransactionType.expense);
      expect(parsed.suggestedRole, AccountRole.expense);
      expect(parsed.category, 'Food & Dining');
      expect(parsed.isHighConfidence, isTrue);
      expect(parsed.financialInstitution, 'HDFC Bank');
    });

    test('parses ICICI Bank online debit correctly', () {
      final notif = RawNotification(
        id: 'n2',
        sender: 'AD-ICICIB',
        body: 'Dear Customer, Acct XX5678 debited with INR 1,299.00 on 13-Nov-26. Info: BIL/ONL/Amazon Pay. Avl Bal: INR 82,340.00.',
        receivedAt: now,
      );

      final parsed = parser.parse(notif);
      expect(parsed, isNotNull);
      expect(parsed!.amountMinorUnits, 129900); // ₹1,299.00
      expect(parsed.isDebit, isTrue);
      expect(parsed.accountMask, '5678');
      expect(parsed.merchant, 'Amazon Pay');
      expect(parsed.category, 'Shopping');
      expect(parsed.balanceMinorUnits, 8234000);
      expect(parsed.financialInstitution, 'ICICI Bank');
    });

    test('parses State Bank of India debit correctly', () {
      final notif = RawNotification(
        id: 'n3',
        sender: 'VM-SBINB',
        body: 'Your A/C XXXXX123456 debited by Rs. 2,500.00 on 13Nov26 transfer to Zomato UPI/431899123456. Bal Rs.14,500.00',
        receivedAt: now,
      );

      final parsed = parser.parse(notif);
      expect(parsed, isNotNull);
      expect(parsed!.amountMinorUnits, 250000); // ₹2,500.00
      expect(parsed.accountMask, '3456');
      expect(parsed.merchant, 'Zomato');
      expect(parsed.referenceNumber, '431899123456');
      expect(parsed.category, 'Food & Dining');
      expect(parsed.financialInstitution, 'State Bank of India');
    });

    test('parses Axis Bank debit with towards merchant pattern', () {
      final notif = RawNotification(
        id: 'n4',
        sender: 'BP-AXISBK',
        body: 'Axis Bank: INR 350.00 debited from A/c no. XX9988 on 13-11-2026 towards Uber. Ref no 431987654321. Avail Bal: INR 12,000.00.',
        receivedAt: now,
      );

      final parsed = parser.parse(notif);
      expect(parsed, isNotNull);
      expect(parsed!.amountMinorUnits, 35000);
      expect(parsed.merchant, 'Uber');
      expect(parsed.category, 'Transportation');
      expect(parsed.referenceNumber, '431987654321');
    });

    test('parses PhonePe push notification', () {
      final notif = RawNotification(
        id: 'n5',
        packageName: 'com.phonepe.app',
        title: 'Payment Successful',
        body: 'Payment of ₹450 to Swiggy was successful.',
        receivedAt: now,
      );

      final parsed = parser.parse(notif);
      expect(parsed, isNotNull);
      expect(parsed!.amountMinorUnits, 45000);
      expect(parsed.isDebit, isTrue);
      expect(parsed.merchant, 'Swiggy');
      expect(parsed.financialInstitution, 'PhonePe');
    });

    test('parses Salary Credit notification into SalaryRoot role', () {
      final notif = RawNotification(
        id: 'n6',
        sender: 'VK-HDFCBK',
        body: 'Salary of Rs 1,50,000.00 credited to A/c **1234 on 01-Nov-26 by ACME CORP. Total Avl Bal: Rs 1,95,000.00',
        receivedAt: now,
      );

      final parsed = parser.parse(notif);
      expect(parsed, isNotNull);
      expect(parsed!.amountMinorUnits, 15000000); // ₹1,50,000.00
      expect(parsed.isDebit, isFalse);
      expect(parsed.suggestedTransactionType, TransactionType.income);
      expect(parsed.suggestedRole, AccountRole.salaryRoot);
    });

    test('parses Credit Card spend into LiabilityCC role', () {
      final notif = RawNotification(
        id: 'n7',
        sender: 'VK-HDFCBK',
        body: "Alert: You've spent INR 3,499.00 on your HDFC Bank Credit Card ending 4321 at ZARA on 13-Nov-26.",
        receivedAt: now,
      );

      final parsed = parser.parse(notif);
      expect(parsed, isNotNull);
      expect(parsed!.amountMinorUnits, 349900);
      expect(parsed.accountType, 'Card');
      expect(parsed.accountMask, '4321');
      expect(
        parsed.suggestedTransactionType,
        TransactionType.creditCardPurchase,
      );
      expect(parsed.suggestedRole, AccountRole.liabilityCc);
      expect(parsed.merchant, 'ZARA');
      expect(parsed.category, 'Shopping');
    });

    test('parses Credit Card Settlement payment', () {
      final notif = RawNotification(
        id: 'n8',
        sender: 'AD-ICICIB',
        body: 'Payment of Rs 25,000.00 received towards your ICICI Bank Credit Card ending 8765 on 10-Nov-26.',
        receivedAt: now,
      );

      final parsed = parser.parse(notif);
      expect(parsed, isNotNull);
      expect(parsed!.amountMinorUnits, 2500000);
      expect(
        parsed.suggestedTransactionType,
        TransactionType.creditCardSettlement,
      );
      expect(parsed.suggestedRole, AccountRole.liabilityCc);
    });

    test('parses ATM cash withdrawal into VirtualWallet role', () {
      final notif = RawNotification(
        id: 'n9',
        sender: 'VK-HDFCBK',
        body: 'INR 5,000.00 withdrawn at ATM from A/C **1234 on 13-Nov-26. Bal: INR 40,000.00',
        receivedAt: now,
      );

      final parsed = parser.parse(notif);
      expect(parsed, isNotNull);
      expect(parsed!.amountMinorUnits, 500000);
      expect(parsed.suggestedTransactionType, TransactionType.atmWithdrawal);
      expect(parsed.suggestedRole, AccountRole.virtualWallet);
    });

    test('rejects non-financial spam or promo messages', () {
      final notif = RawNotification(
        id: 'spam',
        sender: 'VM-OFFERS',
        body:
            'Get 50% discount on branded shoes today only! Click bit.ly/promo',
        receivedAt: now,
      );

      expect(parser.parse(notif), isNull);
    });
  });

  test('Union Bank: "Dr Rs25.00 ... by MB <ref> Fv.<payee>", any sender', () {
    const body =
        'Union Bank of India A/c*0485 Dr Rs25.00 on 15-11-26 19:19 by MB '
        '631977745590 Fv.IRANI, Bal Rs701.83 Not U?Call 18002333/SMS BLOCK '
        '0485 to 8879635472.';
    for (final sender in ['VM-UNIONB', 'AX-UBOIBK', 'Union Bank']) {
      final p = const FinancialParser().parse(
        RawNotification(
          id: 'ubi',
          body: body,
          sender: sender,
          receivedAt: DateTime(2026, 11, 15, 19, 19),
        ),
      )!;
      expect(p.amountMinorUnits, 2500, reason: sender);
      expect(p.isDebit, isTrue);
      expect(p.accountMask, '0485');
      expect(p.referenceNumber, '631977745590');
      expect(p.merchant, 'IRANI'); // not the help-line number
      expect(p.balanceMinorUnits, 70183);
    }
  });

  test('"Cr Rs" is money in', () {
    final p = const FinancialParser().parse(
      RawNotification(
        id: 'cr',
        body:
            'A/c*0485 Cr Rs1,500.00 on 15-11-26 by UPI 512345678901 '
            'Fv.RAVI KUMAR, Bal Rs2,201.83',
        sender: 'VM-UNIONB',
        receivedAt: DateTime(2026, 11, 15),
      ),
    )!;
    expect(p.isDebit, isFalse);
    expect(p.amountMinorUnits, 150000);
  });
}
