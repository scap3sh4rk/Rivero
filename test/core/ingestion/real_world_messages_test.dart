import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ingestion/parser/financial_parser.dart';
import 'package:rivero/core/ingestion/trai_dlt_validator.dart';

/// Messages as banks really send them, arriving through the phone's SMS app
/// (so no bank package, and the bank's name is the notification title).
void main() {
  const parser = FinancialParser();
  final at = DateTime(2026, 11, 14, 9, 3);

  RawNotification sms(String body, {String? title = 'VM-SBIUPI'}) =>
      RawNotification(
        id: 'x',
        body: body,
        title: title,
        sender: title,
        packageName: 'com.samsung.android.messaging',
        receivedAt: at,
      );

  test('SBI UPI debit that has no "Rs" before the amount', () {
    final p = parser.parse(
      sms(
        'Dear UPI user A/C X1234 debited by 500.0 on date 14Nov26 trf to '
        'Rahul Kumar Refno 612345678901 If not u? call 1800111109. -SBI',
      ),
    );
    expect(p, isNotNull);
    expect(p!.amountMinorUnits, 50000);
    expect(p.isDebit, isTrue);
    expect(p.accountMask, '1234');
    expect(p.referenceNumber, '612345678901');
  });

  test('SBI debit with a decimal rupee amount and no currency word', () {
    final p = parser.parse(
      sms(
        'Dear SBI User, your A/c X1234-debited by 1,250.50 on 14Nov26 '
        'transfer to RAHUL Ref No 612345678901. If not done by you, call 1800.',
      ),
    );
    expect(p, isNotNull);
    expect(p!.amountMinorUnits, 125050);
    expect(p.isDebit, isTrue);
  });

  test('"debited for Rs" and "credited with INR" styles', () {
    expect(
      parser
          .parse(
            sms(
              'Your a/c no. XXXXXXXX1234 is debited for Rs.250.00 on 14-11-26 '
              'and a/c XXXX5678 credited (IMPS Ref no 612345678901).',
            ),
          )!
          .amountMinorUnits,
      25000,
    );
  });

  test('a money message with a weak sender is still captured for review', () {
    final p = parser.parse(
      sms('Rs 300 debited from your account to Rahul', title: 'Rahul'),
    );
    expect(p, isNotNull);
    expect(p!.amountMinorUnits, 30000);
  });

  test('chat about numbers is not a transaction', () {
    expect(
      parser.parse(sms('See you at 7:30, bring 2 bags', title: 'Mom')),
      isNull,
    );
  });

  group('UPI app notifications (the amount is often in the title)', () {
    RawNotification upi(
      String title,
      String body, {
      String pkg = 'com.phonepe.app',
    }) => RawNotification(
      id: 'u',
      title: title,
      body: body,
      packageName: pkg,
      receivedAt: at,
    );

    test('"Paid ₹500 to Rahul" in the title, app name in the body', () {
      final p = parser.parse(upi('Paid ₹500 to Rahul Kumar', 'PhonePe'));
      expect(p, isNotNull);
      expect(p!.amountMinorUnits, 50000);
      expect(p.isDebit, isTrue);
      expect(p.merchant, 'Rahul Kumar');
    });

    test('an app the user chose as primary is trusted even if unknown', () {
      const other = 'com.example.newupi';
      final msg = upi(
        'Payment successful',
        'Paid ₹250 to Chai Point',
        pkg: other,
      );
      // Unknown app, no bank sender: a plain parser is unsure.
      final plain = parser.parse(msg);
      final trusted = const FinancialParser(
        dltValidator: TraiDltValidator(extraPackages: {other}),
      ).parse(msg);
      expect(trusted, isNotNull);
      expect(trusted!.amountMinorUnits, 25000);
      expect(trusted.confidenceScore, greaterThan(plain?.confidenceScore ?? 0));
    });

    test('money received shows as income', () {
      final p = parser.parse(
        upi(
          '₹1,200 received from Meera',
          'Google Pay',
          pkg: 'com.google.android.apps.nbu.paisa.user',
        ),
      );
      expect(p, isNotNull);
      expect(p!.amountMinorUnits, 120000);
      expect(p.isDebit, isFalse);
    });
  });
}
