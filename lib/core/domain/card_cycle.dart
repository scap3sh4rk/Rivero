import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/custom_account_types.dart';

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

/// Whether each card's bill can be paid, the same way everywhere (Accounts,
/// the card's own page, Bills, reminders) and the same way Safe to spend
/// sets money aside:
/// * a card with a "bills paid from" account is paid from that account
///   alone; cards sharing one share its balance;
/// * other cards are paid from the bank and cash accounts that are not
///   holding money for a card;
/// * an account the user marked "cannot pay card bills" (a fixed deposit,
///   say) is never counted, even if a card names it;
/// * loans and overdrafts are long-term debt, not a bill: left out.
/// `accounts` are in the home currency (`ExchangeRates.inHome`).
class CardBills {
  CardBills._(this.byCard, this.payerOf, this.all, this.sharing);

  factory CardBills.of(List<PhysicalAccount> accounts) {
    int owedOn(PhysicalAccount a) =>
        a.balanceMinorUnits < 0 ? -a.balanceMinorUnits : 0;
    final banks = {
      for (final a in accounts)
        if (!a.isLiability && a.isActive && a.canPayCardBills) a.id: a,
    };
    final cards = [
      for (final a in accounts)
        if (a.isLiability &&
            a.isActive &&
            !StandardAccountTypes.isLongTermDebt(a.accountType))
          a,
    ];
    // Cards grouped by the account that pays them; '' = no account set
    // (paid from the money not set aside for any card).
    final payerOf = <String, PhysicalAccount>{};
    final groups = <String, List<PhysicalAccount>>{};
    for (final c in cards) {
      final p = banks[c.billsPaidFromAccountId];
      if (p != null) payerOf[c.id] = p;
      (groups[p?.id ?? ''] ??= []).add(c);
    }
    int held(PhysicalAccount a) =>
        a.balanceMinorUnits < 0 ? 0 : a.balanceMinorUnits;
    final pool = banks.values
        .where((b) => !groups.containsKey(b.id))
        .fold<int>(0, (s, b) => s + held(b));

    // Each group is judged as a whole: everything its cards owe against
    // what its account (or the pool) holds, so two cards never both count
    // the same money.
    final byCard = <String, CardAffordability>{};
    final sharing = <String, List<PhysicalAccount>>{};
    var covered = 0;
    var spill = 0; // what payer accounts cannot cover
    var owedTotal = 0;
    for (final MapEntry(key: payer, value: group) in groups.entries) {
      final owed = group.fold<int>(0, (s, c) => s + owedOn(c));
      final available = payer.isEmpty ? pool : held(banks[payer]!);
      owedTotal += owed;
      final a = CardAffordability(owed: owed, available: available);
      for (final c in group) {
        byCard[c.id] = a;
        sharing[c.id] = group;
      }
      if (payer.isEmpty) {
        spill += owed;
      } else {
        covered += owed < available ? owed : available;
        spill += owed > available ? owed - available : 0;
      }
    }
    // Whatever the card accounts cannot cover comes from the other money.
    covered += spill < pool ? spill : pool;
    return CardBills._(
      byCard,
      payerOf,
      CardAffordability(owed: owedTotal, available: covered),
      sharing,
    );
  }

  /// Per card id (cards only; loans and overdrafts have none).
  /// [CardAffordability.owed] is everything owed by the cards paid from the
  /// same place (see [sharing]), against what that place holds.
  final Map<String, CardAffordability> byCard;

  /// The account a card's bills are paid from, if one is set.
  final Map<String, PhysicalAccount> payerOf;

  /// Every card together.
  final CardAffordability all;

  /// Per card id: all cards paid from the same account (itself included).
  final Map<String, List<PhysicalAccount>> sharing;
}
