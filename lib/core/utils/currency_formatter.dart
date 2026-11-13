import 'package:intl/intl.dart';

/// Formatter for financial amounts stored as integer minor units (paise in INR).
/// Strictly prevents floating-point inaccuracies in financial calculations.
abstract final class CurrencyFormatter {
  static final NumberFormat _inrFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final NumberFormat _inrWholeFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// Format an integer minor unit (paise) to standard Indian Rupee notation.
  /// Example:
  /// - `100000` -> `"₹1,000.00"`
  /// - `1234567` -> `"₹12,345.67"`
  /// - `-5000` -> `"-₹50.00"`
  /// - `0` -> `"₹0.00"`
  static String format(
    int minorUnits, {
    bool includeDecimals = true,
    bool showSign = false,
  }) => formatMinorUnits(
    minorUnits,
    includeDecimals: includeDecimals,
    showSign: showSign,
  );

  /// Format an integer minor unit (paise) to standard Indian Rupee notation.
  /// Example:
  /// - `100000` -> `"₹1,000.00"`
  /// - `1234567` -> `"₹12,345.67"`
  /// - `-5000` -> `"-₹50.00"`
  /// - `0` -> `"₹0.00"`
  static String formatMinorUnits(
    int minorUnits, {
    bool includeDecimals = true,
    bool showSign = false,
  }) {
    final isNegative = minorUnits < 0;
    final absMinor = minorUnits.abs();
    final whole = absMinor ~/ 100;
    final paise = absMinor % 100;

    // Use double conversion ONLY for display formatting with NumberFormat,
    // after integer decomposition has already occurred.
    final displayAmount = whole + (paise / 100.0);

    var formatted = includeDecimals
        ? _inrFormatter.format(displayAmount)
        : _inrWholeFormatter.format(whole);

    if (isNegative) {
      formatted = '-$formatted';
    } else if (showSign && minorUnits > 0) {
      formatted = '+$formatted';
    }

    return formatted;
  }

  /// Format integer minor units as a compact string (e.g., ₹1Cr, ₹1.5L, ₹2.5k, ₹500).
  static String formatCompact(int minorUnits) {
    final isNegative = minorUnits < 0;
    final absMinor = minorUnits.abs();
    final whole = absMinor ~/ 100;

    String formatNum(double val) {
      if (val % 1 == 0) return val.toInt().toString();
      return val.toStringAsFixed(1);
    }

    String result;
    if (whole >= 10000000) {
      final cr = whole / 10000000.0;
      result = '₹${formatNum(cr)}Cr';
    } else if (whole >= 100000) {
      final lk = whole / 100000.0;
      result = '₹${formatNum(lk)}L';
    } else if (whole >= 1000) {
      final k = whole / 1000.0;
      result = '₹${formatNum(k)}k';
    } else {
      result = '₹$whole';
    }

    return isNegative ? '-$result' : result;
  }

  /// Parse a currency string to integer minor units safely.
  /// Returns `null` if the input is malformed.
  static int? parseToMinorUnits(String input) {
    final cleaned = input
        .replaceAll('₹', '')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .trim();

    if (cleaned.isEmpty) return null;

    final parts = cleaned.split('.');
    if (parts.length > 2) return null;

    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;

    var paise = 0;
    if (parts.length == 2) {
      final paiseStr = parts[1].padRight(2, '0');
      if (paiseStr.length > 2) {
        // Truncate sub-paise
        paise = int.tryParse(paiseStr.substring(0, 2)) ?? 0;
      } else {
        paise = int.tryParse(paiseStr) ?? 0;
      }
    }

    final total = (whole.abs() * 100) + paise;
    return whole < 0 ? -total : total;
  }
}
