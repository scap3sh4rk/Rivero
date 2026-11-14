import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/providers/app_providers.dart';

void main() {
  test('a message Rivero could not read pre-fills the Log screen', () {
    final p = LogPrefill.fromMessage(
      'Dear UPI user A/C X1234 debited by 500.0 on date 14Nov26 trf to '
      'Rahul Kumar Refno 612345678901',
    );
    expect(p.amountText, '500');
    expect(p.income, isFalse);
    expect(p.note, startsWith('Dear UPI user'));
    expect(p.note.length, lessThanOrEqualTo(80));
  });

  test('credits become income, with the decimals kept', () {
    final p = LogPrefill.fromMessage('Rs 1,250.50 credited to your account');
    expect(p.amountText, '1250.50');
    expect(p.income, isTrue);
  });

  test('no amount found: the note is still filled in', () {
    final p = LogPrefill.fromMessage('Your payment was received. Thank you');
    expect(p.amountText, '');
    expect(p.note, isNotEmpty);
  });
}
