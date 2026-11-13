/// Parses keypad text like "250" or "99.5" into paise without floating point.
int parseAmountMinorUnits(String text) {
  final parts = text.split('.');
  final rupees = int.tryParse(parts[0].isEmpty ? '0' : parts[0]) ?? 0;
  final paise = parts.length > 1
      ? int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0
      : 0;
  return rupees * 100 + paise;
}
