import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Indicates the data reliability level of the calculated Safe-to-Spend value.
enum BalanceReliability {
  /// Authoritative: Account balances and ledger entries synced within the last 24 hours.
  verified,

  /// Estimated: Balances synced between 24 and 72 hours ago; may not reflect pending offline debits.
  estimated,

  /// Stale: Balances have not synced for over 72 hours or are uninitialized.
  stale,
}

/// The comprehensive calculation result for Rivero's Safe-to-Spend financial metric.
@immutable
class SafeToSpendResult {
  const SafeToSpendResult({
    required this.expenseBalance,
    required this.upcomingMandates,
    required this.unsettledCreditCardLiability,
    required this.pendingReimbursements,
    required this.effectiveSafeToSpend,
    required this.nominalSafeToSpend,
    required this.conservativeSafeToSpend,
    required this.dailySpendingPace,
    required this.isDeficit,
    required this.deficitAmount,
    required this.reliability,
    required this.daysRemainingInCycle,
    this.lastSyncedAt,
  });

  /// Total minor units (paise) currently residing in the EXPENSE bucket / accounts.
  final int expenseBalance;

  /// Total minor units of active recurring mandates (UPI autopay, e-NACH)
  /// due before the end of the current paycycle.
  final int upcomingMandates;

  /// Total minor units of unbilled or unpaid credit card liabilities
  /// due before the end of the current paycycle.
  final int unsettledCreditCardLiability;

  /// Total minor units of approved pending reimbursements owed to the user.
  final int pendingReimbursements;

  /// The active Safe-to-Spend value in minor units (paise), incorporating
  /// user preference regarding pending reimbursement inclusion.
  final int effectiveSafeToSpend;

  /// Safe-to-Spend including pending reimbursements:
  /// `expenseBalance - upcomingMandates - unsettledCreditCardLiability + pendingReimbursements`.
  final int nominalSafeToSpend;

  /// Conservative Safe-to-Spend strictly excluding unreceived reimbursements:
  /// `expenseBalance - upcomingMandates - unsettledCreditCardLiability`.
  final int conservativeSafeToSpend;

  /// Minor units the user can spend per remaining calendar day of this paycycle:
  /// `max(0, effectiveSafeToSpend ~/ daysRemainingInCycle)`.
  final int dailySpendingPace;

  /// True if required commitments exceed available funds (`effectiveSafeToSpend < 0`).
  final bool isDeficit;

  /// The absolute shortage in minor units (paise) if [isDeficit] is true; otherwise 0.
  final int deficitAmount;

  /// How fresh and authoritative the underlying balance data is.
  final BalanceReliability reliability;

  /// Calendar days remaining in this paycycle (clamped to minimum 1).
  final int daysRemainingInCycle;

  /// Timestamp of the most recent balance update or bank transaction sync.
  final DateTime? lastSyncedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SafeToSpendResult &&
          runtimeType == other.runtimeType &&
          expenseBalance == other.expenseBalance &&
          upcomingMandates == other.upcomingMandates &&
          unsettledCreditCardLiability == other.unsettledCreditCardLiability &&
          pendingReimbursements == other.pendingReimbursements &&
          effectiveSafeToSpend == other.effectiveSafeToSpend &&
          nominalSafeToSpend == other.nominalSafeToSpend &&
          conservativeSafeToSpend == other.conservativeSafeToSpend &&
          dailySpendingPace == other.dailySpendingPace &&
          isDeficit == other.isDeficit &&
          deficitAmount == other.deficitAmount &&
          reliability == other.reliability &&
          daysRemainingInCycle == other.daysRemainingInCycle &&
          lastSyncedAt == other.lastSyncedAt;

  @override
  int get hashCode => Object.hash(
    expenseBalance,
    upcomingMandates,
    unsettledCreditCardLiability,
    pendingReimbursements,
    effectiveSafeToSpend,
    nominalSafeToSpend,
    conservativeSafeToSpend,
    dailySpendingPace,
    isDeficit,
    deficitAmount,
    reliability,
    daysRemainingInCycle,
    lastSyncedAt,
  );

  @override
  String toString() {
    return 'SafeToSpendResult(STS: $effectiveSafeToSpend, pace: $dailySpendingPace/day, '
        'isDeficit: $isDeficit, deficit: $deficitAmount, reliability: $reliability, '
        'daysLeft: $daysRemainingInCycle)';
  }
}

/// Financial calculator evaluating Safe-to-Spend (STS) and daily spending pace.
///
/// Formula:
/// `STS = Expense Balance - Upcoming Active Mandates - Unsettled CC Liabilities (+ Reimbursements)`
class SafeToSpendCalculator {
  const SafeToSpendCalculator();

  /// Computes the complete Safe-to-Spend analysis.
  ///
  /// All monetary arguments must be in minor units (paise).
  SafeToSpendResult calculate({
    required int expenseBalance,
    required int upcomingMandates,
    required int unsettledCreditCardLiability,
    required int pendingReimbursements,
    required int daysRemainingInCycle,
    DateTime? lastSyncedAt,
    DateTime? asOf,
    bool includePendingReimbursements = false,
  }) {
    final sanitizedDays = math.max(1, daysRemainingInCycle);
    final referenceTime = asOf ?? DateTime.now();

    // Conservative STS excludes pending reimbursements because cash is not yet in hand.
    final conservative =
        expenseBalance - upcomingMandates - unsettledCreditCardLiability;

    // Nominal STS includes pending reimbursements expected to clear.
    final nominal = conservative + pendingReimbursements;

    final effective = includePendingReimbursements ? nominal : conservative;

    final isDeficit = effective < 0;
    final deficitAmount = isDeficit ? -effective : 0;
    final dailyPace = isDeficit ? 0 : effective ~/ sanitizedDays;

    final reliability = _evaluateReliability(
      lastSyncedAt: lastSyncedAt,
      asOf: referenceTime,
    );

    return SafeToSpendResult(
      expenseBalance: expenseBalance,
      upcomingMandates: upcomingMandates,
      unsettledCreditCardLiability: unsettledCreditCardLiability,
      pendingReimbursements: pendingReimbursements,
      effectiveSafeToSpend: effective,
      nominalSafeToSpend: nominal,
      conservativeSafeToSpend: conservative,
      dailySpendingPace: dailyPace,
      isDeficit: isDeficit,
      deficitAmount: deficitAmount,
      reliability: reliability,
      daysRemainingInCycle: sanitizedDays,
      lastSyncedAt: lastSyncedAt,
    );
  }

  /// Determines balance reliability based on the age of the latest sync timestamp.
  BalanceReliability _evaluateReliability({
    required DateTime? lastSyncedAt,
    required DateTime asOf,
  }) {
    if (lastSyncedAt == null) {
      return BalanceReliability.stale;
    }

    final age = asOf.difference(lastSyncedAt);

    if (age.isNegative) {
      // Future timestamp treated as verified.
      return BalanceReliability.verified;
    }

    if (age.inHours < 24) {
      return BalanceReliability.verified;
    } else if (age.inHours < 72) {
      return BalanceReliability.estimated;
    } else {
      return BalanceReliability.stale;
    }
  }
}
