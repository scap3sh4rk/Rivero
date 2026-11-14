import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

/// Where money actually went in a period, without double counting:
/// spends (incl. card purchases) count; refunds give back to their category;
/// self-transfers, card bill payments, ATM withdrawals and income don't.
class SpendingSummary {
  const SpendingSummary({
    required this.total,
    required this.byCategory,
    required this.byDay,
  });

  factory SpendingSummary.of(
    Iterable<LedgerTransaction> txns, {
    required DateTime start,
    required DateTime end,
    Map<String, int> othersShare = const {},
    bool includePlan = true,
    int Function(String accountId, int minor)? toHome,
  }) {
    final from = DateTime(start.year, start.month, start.day);
    final days =
        DateTime(end.year, end.month, end.day).difference(from).inDays + 1;
    final byDay = List<int>.filled(days < 1 ? 1 : days, 0);
    final byCat = <String, int>{};

    for (final t in txns) {
      final applied =
          t.transactionState == TransactionState.confirmed ||
          t.transactionState == TransactionState.reconciled;
      if (!applied || !isSpending(t, includePlan: includePlan)) continue;
      final ts = t.transactionTimestamp;
      if (ts.isBefore(from) || ts.isAfter(end)) continue;

      int delta;
      if (t.amountMinorUnits < 0 && _spendTypes.contains(t.transactionType)) {
        // Shares others owe you on a split bill are not your spending.
        delta = -t.amountMinorUnits - (othersShare[t.id] ?? 0);
        if (delta <= 0) continue;
      } else if (t.amountMinorUnits > 0 &&
          t.transactionType == TransactionType.refund) {
        delta = -t.amountMinorUnits;
      } else {
        continue;
      }
      // Spends on a foreign-currency account count in rupees.
      if (toHome != null) delta = toHome(t.physicalAccountId, delta);
      byCat[t.category] = (byCat[t.category] ?? 0) + delta;
      final day = DateTime(ts.year, ts.month, ts.day).difference(from).inDays;
      if (day >= 0 && day < byDay.length) byDay[day] += delta;
    }

    final cats = byCat.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = cats.fold<int>(0, (s, e) => s + e.value);
    return SpendingSummary(
      total: total,
      byCategory: cats,
      byDay: [for (final d in byDay) d.clamp(0, d.abs())],
    );
  }

  /// Total spent (minor units, never negative).
  final int total;

  /// Category -> spent, largest first.
  final List<MapEntry<String, int>> byCategory;

  /// Spend per calendar day from the start date (index 0 = start day).
  final List<int> byDay;

  /// Whether [t]'s money has actually moved (confirmed or matched).
  static bool applied(LedgerTransaction t) =>
      t.transactionState == TransactionState.confirmed ||
      t.transactionState == TransactionState.reconciled;

  /// Whether [t] is spending (or a refund of spending) by its kind, the
  /// one rule Activity's "Spends" filter, Analytics and the totals share.
  /// Self-transfers, card bills, ATM cash, loans, repayments and hand-set
  /// balances are not spending.
  static bool isSpending(LedgerTransaction t, {bool includePlan = true}) {
    if (t.isInternalTransfer) return false;
    if (!includePlan && t.transactionType == TransactionType.planTransfer) {
      return false;
    }
    if (t.amountMinorUnits < 0) return _spendTypes.contains(t.transactionType);
    return t.transactionType == TransactionType.refund;
  }

  static const Set<TransactionType> _spendTypes = {
    TransactionType.expense,
    TransactionType.cashExpenditure,
    TransactionType.creditCardPurchase,
    // Rent, EMI, family: real money out even though the plan paid it.
    TransactionType.planTransfer,
  };
}
