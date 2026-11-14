import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Semantic tiers for credit line / credit card utilization.
enum CreditUtilizationTier {
  /// <= 10%: Optimal usage. Safest for credit score.
  safe,

  /// 10% - 30%: Acceptable usage. Moderate buffer before score is impacted.
  moderate,

  /// > 30%: Risky / High usage. Directly affects credit score negatively.
  risky,
}

/// Comprehensive analysis of credit line utilization for a credit account.
class CreditUtilization {
  const CreditUtilization({
    required this.creditLimitMinorUnits,
    required this.usedMinorUnits,
    required this.availableMinorUnits,
    required this.utilizationPercent,
    required this.tier,
  });

  /// Factory calculating utilization from limit and liability balance.
  /// Note: In the ledger, liability balance is negative (e.g. -₹14,250), so used is abs().
  factory CreditUtilization.fromBalance({
    required int creditLimitMinorUnits,
    required int balanceMinorUnits,
  }) {
    final used = balanceMinorUnits < 0 ? balanceMinorUnits.abs() : 0;
    final limit = creditLimitMinorUnits > 0 ? creditLimitMinorUnits : 0;
    final available = (limit - used).clamp(0, limit);

    final double percent;
    if (limit > 0) {
      percent = (used / limit) * 100.0;
    } else {
      percent = used > 0 ? 100.0 : 0.0;
    }

    final CreditUtilizationTier tier;
    if (percent <= 10.0) {
      tier = CreditUtilizationTier.safe;
    } else if (percent <= 30.0) {
      tier = CreditUtilizationTier.moderate;
    } else {
      tier = CreditUtilizationTier.risky;
    }

    return CreditUtilization(
      creditLimitMinorUnits: limit,
      usedMinorUnits: used,
      availableMinorUnits: available,
      utilizationPercent: percent,
      tier: tier,
    );
  }

  /// Total sanctioned credit limit in minor units (paise).
  final int creditLimitMinorUnits;

  /// Current utilized / spent credit in minor units.
  final int usedMinorUnits;

  /// Remaining available credit in minor units.
  final int availableMinorUnits;

  /// Current credit utilization percentage (0.0 to 100.0+).
  final double utilizationPercent;

  /// Tier based on the 10% safe / 30% credit score impact rule.
  final CreditUtilizationTier tier;

  /// Short badge label.
  String get badgeLabel {
    switch (tier) {
      case CreditUtilizationTier.safe:
        return 'Safe (<=10%)';
      case CreditUtilizationTier.moderate:
        return 'Moderate (<=30%)';
      case CreditUtilizationTier.risky:
        return 'Affects Score (>30%)';
    }
  }

  /// Color associated with the utilization status.
  Color get statusColor {
    switch (tier) {
      case CreditUtilizationTier.safe:
        return RiveroColors.success; // green
      case CreditUtilizationTier.moderate:
        return RiveroColors.warning; // amber
      case CreditUtilizationTier.risky:
        return RiveroColors.danger; // Rose Red
    }
  }

  /// Informative advisory text for the user.
  /// Pill text: just the percentage; the colour carries the meaning.
  String get pillLabel => '${utilizationPercent.round()}%';

  String get adviceMessage {
    switch (tier) {
      case CreditUtilizationTier.safe:
        return 'Excellent! Using under 10% of your credit limit maximizes your credit score.';
      case CreditUtilizationTier.moderate:
        return 'Healthy utilization. Try to keep balances below 30% before the billing cycle ends.';
      case CreditUtilizationTier.risky:
        return 'Warning: Credit utilization above 30% significantly drops your CIBIL / Experian score. Consider paying down this balance.';
    }
  }
}
