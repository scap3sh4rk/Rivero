/// Largest amount the app accepts (₹100 crore, in paise). Far above any real
/// personal figure, far below where 64-bit integer maths could wrap.
const int maxAmountMinorUnits = 100000000000;

/// Parses typed text like "250" or "99.5" into paise without floating point.
///
/// Returns 0 for anything that is not a plain non-negative amount (empty,
/// "-5", "1e9", "12abc") and for amounts above [maxAmountMinorUnits], so
/// callers treat "invalid" and "nothing entered" the same and never save it.
int parseAmountMinorUnits(String text) {
  final m = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(text.trim());
  if (m == null) return 0;
  final whole = m.group(1) ?? '';
  // 12 digits of rupees is already beyond the cap; refuse before parsing.
  if (whole.length > 12) return 0;
  final rupees = int.tryParse(whole.isEmpty ? '0' : whole) ?? 0;
  final frac = (m.group(2) ?? '').padRight(2, '0').substring(0, 2);
  final value = rupees * 100 + int.parse(frac);
  return value > maxAmountMinorUnits ? 0 : value;
}

/// True when [text] looks like a number but is above the supported maximum.
bool isAmountTooLarge(String text) {
  final m = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(text.trim());
  if (m == null || (m.group(1) ?? '').isEmpty) return false;
  final whole = m.group(1)!;
  if (whole.length > 12) return true;
  return int.parse(whole) * 100 > maxAmountMinorUnits;
}
