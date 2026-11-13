import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// The seven core account roles defined in the Rivero financial domain.
enum AccountRole {
  /// Primary salary or main income account — root of the waterfall allocation.
  salaryRoot,

  /// Day-to-day spending and operational expenses.
  expense,

  /// Long-term investments (SIP, mutual funds, stocks, PPF).
  investment,

  /// Emergency funds, liquidity buffers, and goal savings.
  savings,

  /// User-defined specific-purpose buckets.
  custom,

  /// Credit card accounts tracking outstanding revolving liabilities.
  liabilityCc,

  /// Virtual/prepaid wallets (UPI wallets, prepaid cards).
  virtualWallet;

  /// User-facing human-readable title.
  String get displayName {
    switch (this) {
      case AccountRole.salaryRoot:
        return 'Salary Root';
      case AccountRole.expense:
        return 'Expense';
      case AccountRole.investment:
        return 'Investment';
      case AccountRole.savings:
        return 'Savings';
      case AccountRole.custom:
        return 'Custom Bucket';
      case AccountRole.liabilityCc:
        return 'Credit Card';
      case AccountRole.virtualWallet:
        return 'Virtual Wallet';
    }
  }

  /// System identifier code (e.g., SALARY_ROOT).
  String get code {
    switch (this) {
      case AccountRole.salaryRoot:
        return 'SALARY_ROOT';
      case AccountRole.expense:
        return 'EXPENSE';
      case AccountRole.investment:
        return 'INVESTMENT';
      case AccountRole.savings:
        return 'SAVINGS';
      case AccountRole.custom:
        return 'CUSTOM';
      case AccountRole.liabilityCc:
        return 'LIABILITY_CC';
      case AccountRole.virtualWallet:
        return 'VIRTUAL_WALLET';
    }
  }

  /// Parse an account role from its uppercase string code.
  static AccountRole fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'SALARY_ROOT':
        return AccountRole.salaryRoot;
      case 'EXPENSE':
        return AccountRole.expense;
      case 'INVESTMENT':
        return AccountRole.investment;
      case 'SAVINGS':
        return AccountRole.savings;
      case 'CUSTOM':
        return AccountRole.custom;
      case 'LIABILITY_CC':
        return AccountRole.liabilityCc;
      case 'VIRTUAL_WALLET':
        return AccountRole.virtualWallet;
      default:
        throw ArgumentError('Unknown AccountRole code: $code');
    }
  }

  /// Color accent associated with this role according to Rivero design specs.
  Color get accentColor {
    switch (this) {
      case AccountRole.salaryRoot:
        return RiveroColors.salaryAccent;
      case AccountRole.expense:
        return RiveroColors.expenseAccent;
      case AccountRole.investment:
        return RiveroColors.investmentAccent;
      case AccountRole.savings:
        return RiveroColors.savingsAccent;
      case AccountRole.custom:
        return RiveroColors.customAccent;
      case AccountRole.liabilityCc:
        return RiveroColors.liabilityAccent;
      case AccountRole.virtualWallet:
        return RiveroColors.walletAccent;
    }
  }
}
