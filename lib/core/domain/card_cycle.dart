/// A credit card's billing cycle: the statement is generated on
/// `statementDay` each month and the bill is due on `paymentDueDay`.
/// Every card can have its own.
class CardCycle {
  const CardCycle._({
    required this.cycleStart,
    required this.nextStatement,
    required this.lastStatement,
    required this.dueDate,
    required this.daysToStatement,
    required this.daysToDue,
    required this.cycleDays,
  });

  /// First day of the current cycle (the day after the last statement).
  final DateTime cycleStart;

  /// The day the current cycle closes and its statement is generated.
  final DateTime nextStatement;
  final DateTime lastStatement;

  /// The next payment due date: of the last statement while that is still
  /// ahead, otherwise of the next one.
  final DateTime dueDate;

  /// Days left in the billing cycle (0 = the statement is generated today).
  final int daysToStatement;

  /// Days left to pay (0 = due today).
  final int daysToDue;

  /// Length of the current cycle in days.
  final int cycleDays;

  /// How far through the cycle today is, 0..1.
  double get progress =>
      cycleDays <= 0 ? 0 : 1 - (daysToStatement / cycleDays).clamp(0.0, 1.0);

  static int _clampDay(int year, int month, int day) {
    final last = DateTime(year, month + 1, 0).day;
    return day > last ? last : day;
  }

  /// [day] of the month of [anchor] plus [monthOffset] (clamped to its length).
  static DateTime _inMonth(DateTime anchor, int monthOffset, int day) {
    final m = DateTime(anchor.year, anchor.month + monthOffset);
    return DateTime(m.year, m.month, _clampDay(m.year, m.month, day));
  }

  /// The first date strictly after [after] that falls on [day].
  static DateTime _firstOnDayAfter(DateTime after, int day) {
    for (var k = 0; k < 3; k++) {
      final d = _inMonth(after, k, day);
      if (d.isAfter(after)) return d;
    }
    return _inMonth(after, 3, day);
  }

  /// Null when either day is missing or invalid.
  static CardCycle? of({
    required int? statementDay,
    required int? paymentDueDay,
    required DateTime now,
  }) {
    if (statementDay == null ||
        paymentDueDay == null ||
        statementDay < 1 ||
        statementDay > 31 ||
        paymentDueDay < 1 ||
        paymentDueDay > 31) {
      return null;
    }
    final today = DateTime(now.year, now.month, now.day);
    // Statement dates: the latest on or before today, and the next one.
    var last = _inMonth(today, 0, statementDay);
    if (last.isAfter(today)) last = _inMonth(today, -1, statementDay);
    final next = _inMonth(last, 1, statementDay);
    // Due date of the last statement; if that has passed (the bill was due
    // and is behind us), the one that follows the next statement.
    var due = _firstOnDayAfter(last, paymentDueDay);
    if (due.isBefore(today)) due = _firstOnDayAfter(next, paymentDueDay);
    return CardCycle._(
      cycleStart: last.add(const Duration(days: 1)),
      nextStatement: next,
      lastStatement: last,
      dueDate: due,
      daysToStatement: next.difference(today).inDays,
      daysToDue: due.difference(today).inDays,
      cycleDays: next.difference(last).inDays,
    );
  }
}

/// Whether the money you hold covers what cards need next.
class CardAffordability {
  const CardAffordability({required this.owed, required this.available});

  /// What the card(s) owe (paise, >= 0).
  final int owed;

  /// Bank and cash balances you can pay from (paise, >= 0).
  final int available;

  bool get canPay => available >= owed;

  /// How much is missing (0 when you can pay).
  int get shortBy => canPay ? 0 : owed - available;

  /// What is left after paying.
  int get leftAfter => canPay ? available - owed : 0;
}
