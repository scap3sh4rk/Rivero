import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/currency/currency.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/engine/spending_summary.dart';

void main() {
  final now = DateTime(2026, 11, 14);
  PhysicalAccount account(String id, int balance, String code) =>
      PhysicalAccount(
        id: id,
        name: id,
        institution: 'Bank',
        accountMask: '1234',
        balanceMinorUnits: balance,
        creditLimitMinorUnits: 0,
        accountType: 'Savings',
        currencyCode: code,
        isLiability: false,
        isActive: true,
        includeInNetWorth: true,
        canPayCardBills: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );

  const rates = ExchangeRates({'USD': 8325}); // 1 USD = ₹83.25

  test('converts to rupees in integers, rounding half away from zero', () {
    expect(rates.toHome(10000, 'USD'), 832500); // $100 -> ₹8,325
    expect(rates.toHome(1, 'USD'), 83); // 1¢ -> 83.25 paise -> 83
    expect(rates.toHome(-2, 'USD'), -167); // -166.5 -> -167
    expect(rates.toHome(500, 'INR'), 500);
    // No rate yet: left out rather than guessed.
    expect(rates.toHome(10000, 'EUR'), 0);
    expect(rates.has('EUR'), isFalse);
    expect(ExchangeRates.fromJson(rates.toJson()).paisePerUnit, {'USD': 8325});
  });

  test('accounts in rupees for totals; the originals are untouched', () {
    final usd = account('us', 100000, 'USD'); // $1,000
    final inr = account('in', 500000, 'INR');
    final home = rates.inHome([usd, inr]);
    expect(home.map((a) => a.balanceMinorUnits), [8325000, 500000]);
    expect(usd.balanceMinorUnits, 100000);
  });

  test('a spend on a dollar account counts in rupees', () {
    final t = LedgerTransaction(
      id: 't',
      physicalAccountId: 'us',
      amountMinorUnits: -1000, // $10
      transactionType: TransactionType.expense,
      transactionState: TransactionState.confirmed,
      merchant: 'Cafe',
      category: 'Food',
      transactionTimestamp: now,
      createdAt: now,
      isInternalTransfer: false,
    );
    final s = SpendingSummary.of(
      [t],
      start: now,
      end: now.add(const Duration(hours: 1)),
      toHome: (id, minor) => rates.toHome(minor, id == 'us' ? 'USD' : 'INR'),
    );
    expect(s.total, 83250);
  });

  test('foreign amounts are shown in their own currency', () {
    expect(formatIn(123456, 'USD'), r'$1,234.56');
    expect(formatIn(-5, 'EUR'), '-€0.05');
    expect(formatIn(10000, 'INR'), '₹100.00');
  });
}
