import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/card_cycle.dart';

void main() {
  CardCycle cycle(int s, int d, DateTime now) =>
      CardCycle.of(statementDay: s, paymentDueDay: d, now: now)!;

  test('statement on the 15th, due on the 5th: mid-cycle', () {
    final c = cycle(15, 5, DateTime(2026, 11, 20));
    expect(c.lastStatement, DateTime(2026, 11, 15));
    expect(c.nextStatement, DateTime(2026, 12, 15));
    // The statement day itself starts the next cycle.
    expect(c.cycleStart, DateTime(2026, 11, 15));
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

  group('CardBills: whether each card can be paid', () {
    final at = DateTime(2026, 11, 15);
    PhysicalAccount acc(
      String id,
      int balance, {
      bool card = false,
      bool canPay = true,
      String? paidFrom,
      String type = 'Savings',
    }) => PhysicalAccount(
      id: id,
      name: id,
      institution: id,
      accountMask: '••••',
      accountType: type,
      balanceMinorUnits: balance,
      creditLimitMinorUnits: card ? 10000000 : 0,
      isLiability: card,
      isActive: true,
      includeInNetWorth: true,
      canPayCardBills: canPay,
      billsPaidFromAccountId: paidFrom,
      currencyCode: 'INR',
      sortOrder: 0,
      createdAt: at,
      updatedAt: at,
    );

    test('a card with its own account is judged on that account alone', () {
      final b = CardBills.of([
        acc('salary', 10000000), // ₹1 lakh, not for this card
        acc('slicebank', 30000),
        acc('slice', -50000, card: true, paidFrom: 'slicebank'),
      ]);
      expect(b.byCard['slice']!.canPay, isFalse);
      expect(b.byCard['slice']!.shortBy, 20000);
      expect(b.payerOf['slice']!.id, 'slicebank');
      // All cards together: the salary account can top up the rest.
      expect(b.all.canPay, isTrue);
    });

    test('an account marked as not for card bills is never counted', () {
      final b = CardBills.of([
        acc('spend', 40000),
        acc('fd', 5000000, canPay: false), // a fixed deposit
        acc('hdfc', -100000, card: true, paidFrom: 'fd'),
      ]);
      expect(b.payerOf.containsKey('hdfc'), isFalse);
      expect(b.all.available, 40000);
      expect(b.all.shortBy, 60000);
    });

    test('cards sharing an account share its balance', () {
      final b = CardBills.of([
        acc('pot', 100000),
        acc('a', -60000, card: true, paidFrom: 'pot'),
        acc('b', -60000, card: true, paidFrom: 'pot'),
      ]);
      expect(b.byCard['a']!.canPay, isFalse);
      expect(b.byCard['a']!.shortBy, 20000);
      expect(b.all.shortBy, 20000);
    });

    test('other cards are paid from accounts not holding money for a card', () {
      final b = CardBills.of([
        acc('spend', 40000),
        acc('slicebank', 500000),
        acc('slice', -10000, card: true, paidFrom: 'slicebank'),
        acc('hdfc', -50000, card: true),
      ]);
      expect(b.byCard['hdfc']!.shortBy, 10000);
      expect(b.byCard['slice']!.canPay, isTrue);
    });

    test('cards with no paying account are netted against the rest', () {
      final b = CardBills.of([
        acc('spend', 100000),
        acc('x', -60000, card: true),
        acc('y', -60000, card: true),
      ]);
      // ₹1,000 cannot pay both ₹600 bills: short by ₹200, not "can pay".
      expect(b.byCard['x']!.owed, 120000);
      expect(b.byCard['x']!.shortBy, 20000);
      expect(b.sharing['x']!.map((c) => c.id), ['x', 'y']);
    });

    test('loans are not bills', () {
      final b = CardBills.of([
        acc('bank', 100000),
        acc('home', -250000000, card: true, type: 'Home Loan'),
      ]);
      expect(b.byCard, isEmpty);
      expect(b.all.owed, 0);
    });
  });
}
