import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/design_system/widgets/financial_amount_text.dart';
import 'package:rivero/design_system/widgets/rivero_button.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/design_system/widgets/role_badge.dart';

void main() {
  group('Design System Widget tests', () {
    testWidgets('RiveroCard renders child correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RiveroCard(child: Text('Test Card Content'))),
        ),
      );

      expect(find.text('Test Card Content'), findsOneWidget);
    });

    testWidgets('RiveroButton triggers callback on tap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RiveroButton(
              label: 'Click Me',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Click Me'), findsOneWidget);
      await tester.tap(find.byType(RiveroButton));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('RoleBadge displays role name', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RoleBadge(role: AccountRole.salaryRoot)),
        ),
      );

      expect(find.text('Salary Root'), findsOneWidget);
    });

    testWidgets('FinancialAmountText formats static amount', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FinancialAmountText(minorUnits: 4825000)),
        ),
      );

      expect(find.text('₹48,250.00'), findsOneWidget);
    });
  });
}
