/// Keypad calculator in integer paise (no floating point).
///
/// Supports + − × ÷ with normal precedence and calculator-style %:
/// `500+10%` = 550 (percent of the running total), `200×15%` = 30.
/// Returns null for an unfinished or invalid expression (e.g. ÷0).
int? evaluateExpression(String input) {
  final expr = input.replaceAll(' ', '');
  if (expr.isEmpty) return null;

  // Tokenise into numbers (paise, with a percent flag) and operators.
  final tokens = <Object>[];
  final number = RegExp(r'^(\d+)(?:\.(\d{0,2}))?(%)?');
  var i = 0;
  while (i < expr.length) {
    final m = number.firstMatch(expr.substring(i));
    if (m != null) {
      final whole = int.parse(m.group(1)!);
      final frac = int.parse((m.group(2) ?? '').padRight(2, '0'));
      tokens.add(_Num(whole * 100 + frac, percent: m.group(3) != null));
      i += m.group(0)!.length;
      continue;
    }
    final c = expr[i];
    if (!'+-×÷'.contains(c)) return null;
    tokens.add(c);
    i++;
  }
  if (tokens.isEmpty || tokens.first is! _Num || tokens.last is! _Num) {
    return null;
  }

  // Split into additive terms; each term is a product/quotient chain.
  var total = 0;
  var sign = '+';
  var start = 0;
  for (var k = 0; k <= tokens.length; k++) {
    final atEnd = k == tokens.length;
    if (!atEnd && tokens[k] is! String) continue;
    if (!atEnd && (tokens[k] == '×' || tokens[k] == '÷')) continue;
    final term = tokens.sublist(start, k);
    if (term.isEmpty) return null;
    int? value;
    final single = term.length == 1 ? term.first as _Num : null;
    if (single != null && single.percent && start > 0) {
      // "total ± p%" means p percent of the running total.
      value = _mulDiv(total, single.paise, 10000);
    } else {
      value = _evalProduct(term);
    }
    if (value == null) return null;
    total = sign == '+' ? total + value : total - value;
    if (!atEnd) {
      sign = tokens[k] as String;
      start = k + 1;
    }
  }
  return total;
}

int? _evalProduct(List<Object> term) {
  int value(_Num n) => n.percent ? _mulDiv(n.paise, 1, 100)! : n.paise;
  var acc = value(term.first as _Num);
  for (var k = 1; k < term.length; k += 2) {
    final op = term[k] as String;
    final rhs = value(term[k + 1] as _Num);
    if (op == '×') {
      acc = _mulDiv(acc, rhs, 100)!;
    } else {
      if (rhs == 0) return null;
      acc = _mulDiv(acc, 100, rhs)!;
    }
  }
  return acc;
}

/// a × b ÷ d, rounded half away from zero, via BigInt to avoid overflow.
int? _mulDiv(int a, int b, int d) {
  if (d == 0) return null;
  final n = BigInt.from(a) * BigInt.from(b);
  final q = n ~/ BigInt.from(d);
  final r = n.remainder(BigInt.from(d)).abs() * BigInt.two;
  final roundUp = r >= BigInt.from(d.abs());
  final sign = (n.isNegative != d.isNegative) ? -1 : 1;
  return (q + (roundUp ? BigInt.from(sign) : BigInt.zero)).toInt();
}

class _Num {
  const _Num(this.paise, {required this.percent});
  final int paise;
  final bool percent;
}

/// True when [expr] contains an operator (i.e. it is a calculation).
bool isCalculation(String expr) => RegExp(r'[+\-×÷%]').hasMatch(expr);
