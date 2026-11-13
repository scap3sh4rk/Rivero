import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/ingestion/trai_dlt_validator.dart';

void main() {
  group('TraiDltValidator', () {
    const validator = TraiDltValidator();

    test('validates standard Indian TRAI DLT headers', () {
      expect(validator.isValidDltHeader('VK-HDFCBK'), isTrue);
      expect(validator.isValidDltHeader('AD-ICICIB'), isTrue);
      expect(validator.isValidDltHeader('VM-SBINB'), isTrue);
      expect(validator.isValidDltHeader('BP-AXISBK'), isTrue);
      expect(validator.isValidDltHeader('JDKOTAKB'), isTrue);
      expect(validator.isValidDltHeader('VK-IDFCFB'), isTrue);

      expect(validator.isValidDltHeader('INVALID'), isFalse);
      expect(validator.isValidDltHeader('123456'), isFalse);
      expect(validator.isValidDltHeader('ABC'), isFalse);
      expect(validator.isValidDltHeader(''), isFalse);
    });

    test('extracts 6-character entity code from DLT header', () {
      expect(validator.extractEntityCode('VK-HDFCBK'), 'HDFCBK');
      expect(validator.extractEntityCode('ad-icicib'), 'ICICIB');
      expect(validator.extractEntityCode('VM-SBINB'), 'SBINB');
      expect(validator.extractEntityCode('BPAXISBK'), 'AXISBK');
      expect(validator.extractEntityCode('invalid-string'), isNull);
    });

    test('identifies recognized financial senders via header or package', () {
      expect(validator.isFinancialSender(senderHeader: 'VK-HDFCBK'), isTrue);
      expect(validator.isFinancialSender(senderHeader: 'AD-ICICIB'), isTrue);
      expect(validator.isFinancialSender(senderHeader: 'VM-SBINB'), isTrue);

      expect(
        validator.isFinancialSender(
          packageName: 'com.google.android.apps.nbu.paisa.user',
        ),
        isTrue,
      );
      expect(
        validator.isFinancialSender(packageName: 'com.phonepe.app'),
        isTrue,
      );
      expect(
        validator.isFinancialSender(packageName: 'net.one97.paytm'),
        isTrue,
      );

      expect(validator.isFinancialSender(senderHeader: 'VK-SPAMMY'), isFalse);
      expect(validator.isFinancialSender(packageName: 'com.whatsapp'), isFalse);
      expect(validator.isFinancialSender(), isFalse);
    });

    test('resolves human-readable financial institution and app names', () {
      expect(
        validator.resolveFinancialInstitutionName(senderHeader: 'VK-HDFCBK'),
        'HDFC Bank',
      );
      expect(
        validator.resolveFinancialInstitutionName(senderHeader: 'AD-ICICIB'),
        'ICICI Bank',
      );
      expect(
        validator.resolveFinancialInstitutionName(
          packageName: 'com.phonepe.app',
        ),
        'PhonePe',
      );
      expect(
        validator.resolveFinancialInstitutionName(
          packageName: 'com.google.android.apps.nbu.paisa.user',
        ),
        'Google Pay',
      );
      expect(
        validator.resolveFinancialInstitutionName(senderHeader: 'XX-UNKNOWN'),
        isNull,
      );
    });
  });
}
