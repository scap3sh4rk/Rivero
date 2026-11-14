import 'package:rivero/core/import/statement_parser.dart';
import 'package:rivero/core/utils/amount_parser.dart';

/// Reads transactions from the text lines of a PDF statement (bank, Google
/// Pay, PhonePe...). Each transaction line starts with a date and holds an
/// amount. Money in or out is decided, in order, by:
///   1. the running balance (bank statements): did it go up or down?
///   2. a Dr/Cr mark on the amount;
///   3. words on the line (debit, paid to, sent / credit, received...).
/// Lines it cannot read (headers, totals, opening balance) are skipped.
List<StatementRow> parseStatementText(List<String> lines) {
  final rows = <StatementRow>[];
  int? lastBalance;
  for (final raw in lines) {
    final line = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_skip.hasMatch(line)) {
      // An opening balance line still tells us where the balance starts.
      final open = _amounts(line);
      if (RegExp('opening', caseSensitive: false).hasMatch(line) &&
          open.isNotEmpty) {
        lastBalance = open.last.paise;
      }
      continue;
    }
    final d = _leadingDate(line);
    if (d == null) continue;
    final rest = line.substring(d.length).trim();
    final amounts = _amounts(rest);
    if (amounts.isEmpty) continue;

    final first = amounts.first;
    int? sign;
    int? balance;
    if (amounts.length >= 2) {
      balance = amounts.last.paise;
      if (lastBalance != null) {
        final delta = balance - lastBalance;
        if (delta == -first.paise) sign = -1;
        if (delta == first.paise) sign = 1;
      }
    }
    sign ??= first.mark;
    sign ??= _out.hasMatch(rest)
        ? -1
        : _in.hasMatch(rest)
        ? 1
        : null;
    if (balance != null) lastBalance = balance;
    if (sign == null || first.paise == 0) continue;

    var desc = rest
        .substring(0, first.start)
        .replaceAll(_noise, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (desc.length > 120) desc = desc.substring(0, 120);
    rows.add(
      StatementRow(
        date: d.date,
        description: desc.isEmpty ? 'Statement entry' : desc,
        amountMinorUnits: sign * first.paise,
      ),
    );
  }
  return rows;
}

final _skip = RegExp(
  'opening balance|closing balance|^total|grand total|brought forward|'
  'carried forward|statement period|statement summary',
  caseSensitive: false,
);
final _out = RegExp(
  r'\b(debit(ed)?|dr|paid to|paid|sent to|sent|withdrawal|purchase|spent)\b',
  caseSensitive: false,
);
final _in = RegExp(
  r'\b(credit(ed)?|cr|received from|received|deposit|refund|cashback)\b',
  caseSensitive: false,
);

/// Column words left in a description ("DEBIT", "UPI Transaction ID").
final _noise = RegExp(
  r'\b(debit|credit|dr|cr)\b|₹|\bINR\b|\bRs\.?',
  caseSensitive: false,
);

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

int _year(String y) => y.length == 2 ? 2000 + int.parse(y) : int.parse(y);

/// A date at the very start of [line], in any of the usual statement
/// formats: 03/11/2026, 03-11-26, 2026-11-03, 03 Nov 2026, 03-Nov-26,
/// 03 Nov, 2026 (Google Pay), Nov 03, 2026 (PhonePe).
({DateTime date, int length})? _leadingDate(String line) {
  DateTime? valid(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) {
      return null;
    }
    final dt = DateTime(y, m, d);
    return dt.month == m ? dt : null; // 31 Feb is not a date
  }

  var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(line);
  if (m != null) {
    final dt = valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    return dt == null ? null : (date: dt, length: m[0]!.length);
  }
  m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2}|\d{4})\b')
      .firstMatch(line);
  if (m != null) {
    final dt = valid(_year(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    return dt == null ? null : (date: dt, length: m[0]!.length);
  }
  m = RegExp(r'^(\d{1,2})[\s\-]([A-Za-z]{3})[A-Za-z]*,?[\s\-](\d{2}|\d{4})\b')
      .firstMatch(line);
  if (m != null) {
    final mon = _months[m[2]!.toLowerCase()];
    final dt = mon == null ? null : valid(_year(m[3]!), mon, int.parse(m[1]!));
    return dt == null ? null : (date: dt, length: m[0]!.length);
  }
  m = RegExp(r'^([A-Za-z]{3})[A-Za-z]* (\d{1,2}),? (\d{4})\b').firstMatch(line);
  if (m != null) {
    final mon = _months[m[1]!.toLowerCase()];
    final dt = mon == null
        ? null
        : valid(int.parse(m[3]!), mon, int.parse(m[2]!));
    return dt == null ? null : (date: dt, length: m[0]!.length);
  }
  return null;
}

/// Money on a line: "1,234.50", "₹450", "Rs. 99", with an optional Dr/Cr.
/// Plain numbers need two decimals so reference numbers are not read as
/// amounts; with ₹ / Rs / INR in front, whole rupees are fine.
List<({int paise, int? mark, int start})> _amounts(String s) {
  final out = <({int paise, int? mark, int start})>[];
  final re = RegExp(
    r'(?:(₹|Rs\.?|INR)\s?)?(\d{1,3}(?:,\d{2,3})+|\d+)(\.\d{1,2})?(?:\s?(Dr|Cr)\b)?',
    caseSensitive: false,
  );
  for (final m in re.allMatches(s)) {
    final hasCurrency = m[1] != null;
    final decimals = m[3];
    if (!hasCurrency && (decimals == null || decimals.length != 3)) continue;
    // Not part of a longer token (a date, an ID like ABC123.45).
    if (m.start > 0 &&
        RegExp(r'[\w/.\-]').hasMatch(s[m.start - 1]) &&
        !hasCurrency) {
      continue;
    }
    final whole = int.tryParse(m[2]!.replaceAll(',', ''));
    if (whole == null || whole > maxAmountMinorUnits ~/ 100) continue;
    final frac = (decimals ?? '.00').substring(1).padRight(2, '0');
    final mark = m[4]?.toLowerCase();
    out.add((
      paise: whole * 100 + int.parse(frac),
      mark: mark == 'dr' ? -1 : (mark == 'cr' ? 1 : null),
      start: m.start,
    ));
  }
  return out;
}
