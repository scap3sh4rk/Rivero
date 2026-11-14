import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/utils/currency_formatter.dart';

/// Rupees are the home currency: Safe to spend, plan and totals are in ₹.
const homeCurrency = 'INR';

/// Currencies an account can hold (all with two decimals, so amounts stay
/// integer cents/paise everywhere).
// ponytail: two-decimal currencies only; add a minor-unit table before JPY.
const currencySymbols = {
  'INR': '₹',
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'AED': 'AED ',
  'SGD': r'S$',
  'CAD': r'C$',
  'AUD': r'A$',
};

/// [minor] in [code]'s own notation ("$12.50"); rupees as usual.
String formatIn(int minor, String code) {
  if (code == homeCurrency) return CurrencyFormatter.format(minor);
  final f = NumberFormat.currency(
    locale: 'en_US',
    symbol: currencySymbols[code] ?? '$code ',
    decimalDigits: 2,
  );
  final abs = minor.abs();
  // Display only: the integer split happens first, as in CurrencyFormatter.
  final s = f.format(abs ~/ 100 + (abs % 100) / 100.0);
  return minor < 0 ? '-$s' : s;
}

/// [v] on account [a] in the account's own currency. [money] is the
/// screen's rupee formatter, which also hides amounts in privacy mode.
String accountMoney(PhysicalAccount a, int v, String Function(int) money) =>
    a.currencyCode == homeCurrency || money(0).startsWith('•')
    ? money(v)
    : formatIn(v, a.currencyCode);

/// The user's rates to rupees: paise per one unit of each currency
/// (1 USD = ₹83.25 is stored as 8325). Typed in by the user; Rivero makes
/// no network calls.
class ExchangeRates {
  const ExchangeRates(this.paisePerUnit);

  factory ExchangeRates.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const ExchangeRates({});
    return ExchangeRates((jsonDecode(raw) as Map).cast<String, int>());
  }

  final Map<String, int> paisePerUnit;

  String toJson() => jsonEncode(paisePerUnit);

  bool has(String code) =>
      code == homeCurrency || (paisePerUnit[code] ?? 0) > 0;

  /// [minor] (cents of [code]) in paise, rounded half away from zero.
  /// Without a rate the amount cannot be counted, so it is 0.
  int toHome(int minor, String code) {
    if (code == homeCurrency) return minor;
    final rate = paisePerUnit[code];
    if (rate == null || rate <= 0) return 0;
    final p = minor.abs() * rate;
    final v = (p + 50) ~/ 100;
    return minor < 0 ? -v : v;
  }

  /// Copies of [accounts] with balance and limit in rupees, for totals and
  /// Safe to spend. Never saved: the real balances stay in their currency.
  List<PhysicalAccount> inHome(List<PhysicalAccount> accounts) => accounts
      .map(
        (a) => a.currencyCode == homeCurrency
            ? a
            : a.copyWith(
                balanceMinorUnits: toHome(a.balanceMinorUnits, a.currencyCode),
                creditLimitMinorUnits: toHome(
                  a.creditLimitMinorUnits,
                  a.currencyCode,
                ),
              ),
      )
      .toList();
}
