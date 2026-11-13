import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

void main() {
  group('AccountRole tests', () {
    test('all seven core roles exist with correct codes', () {
      expect(AccountRole.salaryRoot.code, equals('SALARY_ROOT'));
      expect(AccountRole.expense.code, equals('EXPENSE'));
      expect(AccountRole.investment.code, equals('INVESTMENT'));
      expect(AccountRole.savings.code, equals('SAVINGS'));
      expect(AccountRole.custom.code, equals('CUSTOM'));
      expect(AccountRole.liabilityCc.code, equals('LIABILITY_CC'));
      expect(AccountRole.virtualWallet.code, equals('VIRTUAL_WALLET'));
    });

    test('parse from valid string codes', () {
      expect(
        AccountRole.fromCode('SALARY_ROOT'),
        equals(AccountRole.salaryRoot),
      );
      expect(AccountRole.fromCode('expense'), equals(AccountRole.expense));
      expect(
        AccountRole.fromCode('INVESTMENT'),
        equals(AccountRole.investment),
      );
      expect(AccountRole.fromCode('savings'), equals(AccountRole.savings));
      expect(AccountRole.fromCode('custom'), equals(AccountRole.custom));
      expect(
        AccountRole.fromCode('LIABILITY_CC'),
        equals(AccountRole.liabilityCc),
      );
      expect(
        AccountRole.fromCode('VIRTUAL_WALLET'),
        equals(AccountRole.virtualWallet),
      );
    });

    test('throws ArgumentError on invalid code', () {
      expect(() => AccountRole.fromCode('INVALID_ROLE'), throwsArgumentError);
    });

    test('roles have correct accent colors according to specification', () {
      expect(
        AccountRole.salaryRoot.accentColor,
        equals(RiveroColors.salaryAccent),
      );
      expect(
        AccountRole.expense.accentColor,
        equals(RiveroColors.expenseAccent),
      );
      expect(
        AccountRole.investment.accentColor,
        equals(RiveroColors.investmentAccent),
      );
      expect(
        AccountRole.savings.accentColor,
        equals(RiveroColors.savingsAccent),
      );
      expect(AccountRole.custom.accentColor, equals(RiveroColors.customAccent));
      expect(
        AccountRole.liabilityCc.accentColor,
        equals(RiveroColors.liabilityAccent),
      );
      expect(
        AccountRole.virtualWallet.accentColor,
        equals(RiveroColors.walletAccent),
      );
    });
  });
}
