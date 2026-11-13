import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/engine/spending_summary.dart';

LedgerTransaction _t(
  String id,
  int amount,
  TransactionType type,
  String category,
  DateTime at, {
  TransactionState state = TransactionState.confirmed,
  bool transfer = false,
}) => LedgerTransaction(
  id: id,
  physicalAccountId: 'a',
  amountMinorUnits: amount,
  transactionType: type,
  transactionState: state,
  merchant: id,
  category: category,
  transactionTimestamp: at,
  isInternalTransfer: transfer,
  createdAt: at,
);

void main() {
  final start = DateTime(2026, 11);
  final end = DateTime(2026, 11, 14, 23);

  test('counts real spending only, no double counting', () {
    final s = SpendingSummary.of(
      [
        _t(
          'food',
          -50000,
          TransactionType.expense,
          'Food',
          DateTime(2026, 11, 2),
        ),
        _t(
          'card',
          -20000,
          TransactionType.creditCardPurchase,
          'Shopping',
          DateTime(2026, 11, 3),
        ),
        _t(
          'bill',
          -20000,
          TransactionType.creditCardSettlement,
          'Bills',
          DateTime(2026, 11, 10),
        ),
        _t(
          'self',
          -100000,
          TransactionType.expense,
          'Other',
          DateTime(2026, 11, 4),
          transfer: true,
        ),
        _t(
          'atm',
          -30000,
          TransactionType.atmWithdrawal,
          'Cash',
          DateTime(2026, 11, 5),
        ),
        _t(
          'salary',
          9000000,
          TransactionType.income,
          'Income',
          DateTime(2026, 11),
        ),
        _t(
          'refund',
          5000,
          TransactionType.refund,
          'Shopping',
          DateTime(2026, 11, 6),
        ),
        _t(
          'pending',
          -7000,
          TransactionType.expense,
          'Food',
          DateTime(2026, 11, 7),
          state: TransactionState.needsReview,
        ),
        _t(
          'old',
          -9000,
          TransactionType.expense,
          'Food',
          DateTime(2026, 10, 30),
        ),
      ],
      start: start,
      end: end,
    );
    expect(s.total, 50000 + 20000 - 5000);
    expect(s.byCategory.map((e) => e.key), ['Food', 'Shopping']);
    expect(s.byCategory.last.value, 15000);
    expect(s.byDay.length, 14);
    expect(s.byDay[1], 50000); // 2 Nov
    expect(s.byDay[5], 0); // a refund-only day never shows negative spend
  });
}
