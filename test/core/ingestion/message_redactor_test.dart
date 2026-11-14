import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/ingestion/message_redactor.dart';

void main() {
  test('digits, UPI IDs and names are hidden; the wording is kept', () {
    final r = redactMessage(
      'Rs 4,250.00 debited from A/c XX4321 on 14-11-26 to Ravi Kumar '
      'UPI ref 431298765 VPA ravi.k@okhdfc',
    );
    expect(
      r,
      'Rs 1,111.11 debited from A/c XX1111 on 11-11-11 to NAME '
      'UPI ref 111111111 VPA name@okhdfc',
    );
  });

  test('the report link opens the bank-message form, filled in', () {
    final u = bankMessageIssueUrl(message: 'Rs 1 paid', sender: 'VM-SBIUPI');
    expect(u.host, 'github.com');
    expect(u.queryParameters['template'], 'bank_message_format.yml');
    expect(u.queryParameters['message'], 'Rs 1 paid');
    expect(u.queryParameters['sender'], 'VM-SBIUPI');
  });
}
