import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/utils/calc.dart';

void main() {
  test('basic arithmetic with precedence, in paise', () {
    expect(evaluateExpression('120+80'), 20000);
    expect(evaluateExpression('120+80×2'), 28000);
    expect(evaluateExpression('1000-250.50'), 74950);
    expect(evaluateExpression('3000÷4'), 75000);
    expect(evaluateExpression('1000÷3'), 33333); // 333.33, no floats
    expect(evaluateExpression('2.5×2.5'), 625); // 6.25
  });

  test('calculator-style percent', () {
    expect(evaluateExpression('500+10%'), 55000);
    expect(evaluateExpression('500-10%'), 45000);
    expect(evaluateExpression('200×15%'), 3000);
    expect(evaluateExpression('18%'), 18);
  });

  test('unfinished or invalid expressions return null', () {
    expect(evaluateExpression(''), isNull);
    expect(evaluateExpression('120+'), isNull);
    expect(evaluateExpression('×5'), isNull);
    expect(evaluateExpression('5÷0'), isNull);
    expect(evaluateExpression('5a'), isNull);
  });

  test('isCalculation', () {
    expect(isCalculation('250'), isFalse);
    expect(isCalculation('250+1'), isTrue);
  });
}
