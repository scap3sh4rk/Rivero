import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/domain/card_cycle.dart';

void main() {
  CardCycle cycle(int s, int d, DateTime now) =>
      CardCycle.of(statementDay: s, paymentDueDay: d, now: now)!;

  test('statement on the 15th, due on the 5th: mid-cycle', () {
    final c = cycle(15, 5, DateTime(2026, 11, 20));
    expect(c.lastStatement, DateTime(2026, 11, 15));
    expect(c.nextStatement, DateTime(2026, 12, 15));
    expect(c.cycleStart, DateTime(2026, 11, 16));
    expect(c.daysToStatement, 25);
    // The 15 Nov statement is due on 5 Dec.
    expect(c.dueDate, DateTime(2026, 12, 5));
    expect(c.daysToDue, 15);
  });

  test('due date later in the same month as the statement', () {
    final c = cycle(5, 25, DateTime(2026, 11, 10));
    expect(c.lastStatement, DateTime(2026, 11, 5));
    expect(c.dueDate, DateTime(2026, 11, 25));
    expect(c.daysToDue, 15);
    expect(c.daysToStatement, 25);
  });

  test('after the due date the next bill is the one that counts', () {
    final c = cycle(5, 25, DateTime(2026, 11, 28));
    expect(c.dueDate, DateTime(2026, 12, 25));
  });

  test('statement day today: a fresh cycle starts, due date ahead', () {
    final c = cycle(15, 5, DateTime(2026, 11, 15));
    expect(c.daysToStatement, 30);
    expect(c.lastStatement, DateTime(2026, 11, 15));
    expect(c.dueDate, DateTime(2026, 12, 5));
  });

  test('the 31st clamps to short months and wraps the year', () {
    final c = cycle(31, 20, DateTime(2027, 2, 10));
    expect(c.lastStatement, DateTime(2027, 1, 31));
    expect(c.nextStatement, DateTime(2027, 2, 28));
    expect(c.daysToStatement, 18);
    final y = cycle(25, 10, DateTime(2026, 12, 30));
    expect(y.lastStatement, DateTime(2026, 12, 25));
    expect(y.nextStatement, DateTime(2027, 1, 25));
    expect(y.dueDate, DateTime(2027, 1, 10));
  });

  test('missing or invalid days give no cycle', () {
    final now = DateTime(2026, 11);
    expect(
      CardCycle.of(statementDay: null, paymentDueDay: 5, now: now),
      isNull,
    );
    expect(CardCycle.of(statementDay: 0, paymentDueDay: 5, now: now), isNull);
    expect(CardCycle.of(statementDay: 5, paymentDueDay: 32, now: now), isNull);
  });

  test('affordability: can pay, or how much is missing', () {
    const ok = CardAffordability(owed: 300000, available: 500000);
    expect(ok.canPay, isTrue);
    expect(ok.leftAfter, 200000);
    const short = CardAffordability(owed: 800000, available: 500000);
    expect(short.canPay, isFalse);
    expect(short.shortBy, 300000);
  });
}
