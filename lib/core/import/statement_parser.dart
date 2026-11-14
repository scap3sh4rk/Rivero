import 'package:rivero/core/ingestion/parser/message_intent.dart';

/// One line of a bank statement. Negative amount = money out.
class StatementRow {
  const StatementRow({
    required this.date,
    required this.description,
    required this.amountMinorUnits,
  });

  final DateTime date;
  final String description;
  final int amountMinorUnits;
}

/// Splits one CSV line, honouring quoted fields ("a, b" stays one field).
List<String> splitCsvLine(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        cur.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      out.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  out.add(cur.toString().trim());
  return out;
}

int? _paise(String raw) {
  var s = raw
      .replaceAll(RegExp(r'[₹,\s]'), '')
      .replaceAll(RegExp(r'inr|rs\.?', caseSensitive: false), '');
  var sign = 1;
  if (RegExp(r'dr$', caseSensitive: false).hasMatch(s)) {
    sign = -1;
    s = s.substring(0, s.length - 2);
  } else if (RegExp(r'cr$', caseSensitive: false).hasMatch(s)) {
    s = s.substring(0, s.length - 2);
  }
  if (s.startsWith('-')) {
    sign = -sign;
    s = s.substring(1);
  }
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  return sign *
      (int.parse(m.group(1)!) * 100 +
          int.parse((m.group(2) ?? '').padRight(2, '0')));
}

DateTime? _date(String raw) {
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(raw.trim());
  if (iso != null) {
    return DateTime(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  return extractNoticeDate(raw);
}

/// Parses a bank statement exported as CSV. Finds the header row by its
/// column names (date, description/narration/particulars, and either
/// debit+credit or amount), then reads every row below it. Rows that cannot
/// be read (opening balance, totals, blank) are skipped.
List<StatementRow> parseStatementCsv(String csv) {
  final lines = csv.split(RegExp(r'\r?\n'));
  int? dateCol;
  int? descCol;
  int? debitCol;
  int? creditCol;
  int? amountCol;
  var start = -1;
  for (var i = 0; i < lines.length && start < 0; i++) {
    final cells = splitCsvLine(lines[i]).map((c) => c.toLowerCase()).toList();
    int? find(List<String> names) {
      for (var j = 0; j < cells.length; j++) {
        if (names.any(cells[j].contains)) return j;
      }
      return null;
    }

    final d = find(['date']);
    final desc = find([
      'narration',
      'description',
      'particulars',
      'remarks',
      'details',
    ]);
    final dr = find(['debit', 'withdrawal', 'dr amount']);
    final cr = find(['credit', 'deposit', 'cr amount']);
    final amt = find(['amount']);
    if (d != null &&
        desc != null &&
        ((dr != null && cr != null) || amt != null)) {
      dateCol = d;
      descCol = desc;
      debitCol = dr;
      creditCol = cr;
      amountCol = (dr != null && cr != null) ? null : amt;
      start = i + 1;
    }
  }
  if (start < 0) return const [];

  final rows = <StatementRow>[];
  for (final line in lines.skip(start)) {
    if (line.trim().isEmpty) continue;
    final c = splitCsvLine(line);
    String at(int? i) => i != null && i < c.length ? c[i] : '';
    final date = _date(at(dateCol));
    if (date == null) continue;
    int? amount;
    if (amountCol != null) {
      amount = _paise(at(amountCol));
    } else {
      final out = _paise(at(debitCol));
      final into = _paise(at(creditCol));
      if (out != null && out != 0) {
        amount = -out.abs();
      } else if (into != null && into != 0) {
        amount = into.abs();
      }
    }
    if (amount == null || amount == 0) continue;
    final desc = at(descCol);
    rows.add(
      StatementRow(
        date: date,
        description: desc.isEmpty ? 'Statement entry' : desc,
        amountMinorUnits: amount,
      ),
    );
  }
  return rows;
}
