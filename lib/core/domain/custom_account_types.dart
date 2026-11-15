import 'package:flutter/material.dart';

/// Predefined standard account type constants.
abstract final class StandardAccountTypes {
  static const String salary = 'Salary';
  static const String savings = 'Savings';
  static const String expense = 'Daily Expense';
  static const String creditCard = 'Credit Card';
  static const String creditLine = 'Credit Line';
  static const String digitalWallet = 'Digital Wallet';
  static const String cash = 'Cash';
  static const String investment = 'Investment / Demat';
  static const String fixedDeposit = 'Fixed Deposit';
  static const String loan = 'Personal / Auto Loan';
  static const String overdraft = 'Bank Overdraft';

  static const List<String> defaultList = [
    salary,
    savings,
    expense,
    creditCard,
    creditLine,
    digitalWallet,
    cash,
    investment,
    fixedDeposit,
    loan,
    overdraft,
  ];

  /// A loan or overdraft (also custom types such as "Home Loan"): long-term
  /// debt, never a bill to clear from this month's money.
  static bool isLongTermDebt(String type) {
    final t = type.toLowerCase();
    return t.contains('loan') || t.contains('overdraft');
  }

  /// Suggested icon for an account type.
  static IconData getIcon(String type) {
    switch (type.toLowerCase()) {
      case 'salary':
        return Icons.work_outline_rounded;
      case 'savings':
        return Icons.savings_outlined;
      case 'daily expense':
      case 'expense':
        return Icons.credit_card_outlined;
      case 'credit card':
      case 'credit line':
        return Icons.credit_score_outlined;
      case 'digital wallet':
      case 'wallet':
        return Icons.account_balance_wallet_outlined;
      case 'cash':
        return Icons.payments_outlined;
      case 'investment / demat':
      case 'investment':
        return Icons.trending_up_rounded;
      case 'fixed deposit':
        return Icons.lock_clock_outlined;
      case 'loan':
      case 'personal / auto loan':
        return Icons.money_off_csred_outlined;
      case 'overdraft':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.account_balance_rounded;
    }
  }
}
