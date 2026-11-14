import 'package:rivero/core/ingestion/parser/message_intent.dart';

/// What a scanned bill most likely says. Every field is a suggestion the
/// user confirms before anything is saved.
class BillDraft {
  const BillDraft({
    this.amountMinorUnits,
    this.merchant,
    this.date,
    this.category,
  });

  final int? amountMinorUnits;
  final String? merchant;
  final DateTime? date;
  final String? category;
}

final _money = RegExp(
  r'(?:₹|rs\.?|inr)?\s*(\d{1,3}(?:,\d{2,3})+|\d+)(?:\.(\d{1,2}))?',
  caseSensitive: false,
);
final _totalLine = RegExp(
  r'\b(grand\s*total|net\s*(?:amount|payable|total)|total\s*(?:amount|payable|due)?|amount\s*(?:due|payable|paid)|to\s*pay|bill\s*amount)\b',
  caseSensitive: false,
);
final _noise = RegExp(
  r'\b(invoice|receipt|tax|gst|gstin|bill\s*no|order|table|cashier|date|time|phone|ph|tel|fssai|thank)\b',
  caseSensitive: false,
);

int? _amountIn(String line) {
  int? best;
  for (final m in _money.allMatches(line)) {
    final whole = int.tryParse(m.group(1)!.replaceAll(',', ''));
    if (whole == null) continue;
    final frac = int.parse((m.group(2) ?? '').padRight(2, '0'));
    final v = whole * 100 + frac;
    if (best == null || v > best) best = v;
  }
  return best;
}

/// Reads OCR text from a bill. Amount: the figure on the "total" line (the
/// last such line wins, since subtotals come first); otherwise the largest
/// figure. Merchant: the first line near the top that looks like a name.
BillDraft parseBillText(String text) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  int? amount;
  for (var i = 0; i < lines.length; i++) {
    if (!_totalLine.hasMatch(lines[i]) ||
        lines[i].toLowerCase().contains('sub')) {
      continue;
    }
    // The figure may sit on the same line or the next one.
    amount =
        _amountIn(lines[i]) ??
        (i + 1 < lines.length ? _amountIn(lines[i + 1]) : null) ??
        amount;
  }
  if (amount == null) {
    for (final l in lines) {
      final v = _amountIn(l);
      if (v != null && (amount == null || v > amount)) amount = v;
    }
  }

  String? merchant;
  for (final l in lines.take(5)) {
    final letters = l.replaceAll(RegExp('[^A-Za-z]'), '');
    if (letters.length >= 3 &&
        !_noise.hasMatch(l) &&
        !RegExp(r'\d{4,}').hasMatch(l)) {
      merchant = l.length > 40 ? l.substring(0, 40) : l;
      break;
    }
  }

  final lower = text.toLowerCase();
  String? category;
  const guesses = {
    'Food': [
      'restaurant',
      'cafe',
      'café',
      'kitchen',
      'biryani',
      'pizza',
      'swiggy',
      'zomato',
      'bakery',
      'hotel',
      'dhaba',
    ],
    'Transport': [
      'petrol',
      'fuel',
      'diesel',
      'uber',
      'ola',
      'metro',
      'parking',
      'toll',
    ],
    'Health': [
      'pharmacy',
      'medical',
      'chemist',
      'hospital',
      'clinic',
      'apollo',
    ],
    'Shopping': [
      'mart',
      'supermarket',
      'store',
      'retail',
      'fashion',
      'dmart',
      'bazaar',
    ],
    'Bills': ['electricity', 'broadband', 'recharge', 'water bill', 'gas'],
  };
  for (final e in guesses.entries) {
    if (e.value.any(lower.contains)) {
      category = e.key;
      break;
    }
  }

  return BillDraft(
    amountMinorUnits: amount,
    merchant: merchant,
    date: extractNoticeDate(text),
    category: category,
  );
}
