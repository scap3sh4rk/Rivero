import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_group.dart';

void main() {
  final at = DateTime(2026, 2, 2);
  PhysicalAccount acc(
    String type, {
    bool liability = false,
    int balance = 0,
    int? rate,
    DateTime? start,
    DateTime? maturity,
  }) => PhysicalAccount(
    id: type,
    name: type,
    institution: 'Bank',
    accountMask: '1234',
    accountType: type,
    balanceMinorUnits: balance,
    creditLimitMinorUnits: 0,
    isLiability: liability,
    isActive: true,
    includeInNetWorth: true,
    currencyCode: 'INR',
    sortOrder: 0,
    fdRateBps: rate,
    fdStartDate: start,
    fdMaturityDate: maturity,
    createdAt: at,
    updatedAt: at,
  );

  test('every account lands in one section', () {
    expect(AccountGroup.of(acc('Savings')), AccountGroup.bank);
    expect(AccountGroup.of(acc('Cash')), AccountGroup.bank);
    expect(AccountGroup.of(acc('Investment / Demat')), AccountGroup.investment);
    expect(AccountGroup.of(acc('Fixed Deposit')), AccountGroup.deposit);
    expect(
      AccountGroup.of(acc('Credit Card', liability: true)),
      AccountGroup.card,
    );
    expect(
      AccountGroup.of(acc('Home Loan', liability: true)),
      AccountGroup.loan,
    );
  });

  test('FD value: quarterly compounding, in whole paise', () {
    // ₹1,00,000 at 7% for one year, compounded quarterly:
    // 1.0175^4 = 1.0718590; each quarter is credited in whole paise,
    // as banks post it: ₹1,07,185.91.
    final v = FixedDeposit.valueOn(
      principal: 10000000,
      rateBps: 700,
      start: DateTime(2026, 2, 2),
      on: DateTime(2027, 2, 2),
    );
    expect(v, 10718591);
    // Half a quarter extra: simple interest for those days.
    final more = FixedDeposit.valueOn(
      principal: 10000000,
      rateBps: 700,
      start: DateTime(2026, 2, 2),
      on: DateTime(2027, 3, 19),
    );
    expect(more, 10718591 + (10718591 * 700 * 45 + 1825000) ~/ 3650000);
    final fd = acc(
      'Fixed Deposit',
      balance: 10000000,
      rate: 700,
      start: DateTime(2026, 2, 2),
      maturity: DateTime(2027, 2, 2),
    );
    expect(FixedDeposit.maturityValue(fd), 10718591);
    // After maturity it stops growing.
    expect(FixedDeposit.valueToday(fd, DateTime(2028, 2, 2)), 10718591);
  });

  test('section order and folding survive a round trip', () {
    final p = const AccountGroupPrefs()
        .reordered([AccountGroup.card, AccountGroup.bank])
        .toggled(AccountGroup.loan);
    final back = AccountGroupPrefs.fromJson(p.toJson());
    expect(back.order.first, AccountGroup.card);
    expect(back.order.length, AccountGroup.values.length); // rest appended
    expect(back.collapsed, {AccountGroup.loan});
  });
}
