import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/main.dart';

void main() {
  testWidgets('RiveroApp renders foundation screen and toggles privacy mode', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: RiveroApp()));
    await tester.pumpAndSettle();

    expect(find.text('Rivero'), findsOneWidget);
    expect(find.text('SAFE TO SPEND'), findsOneWidget);
    expect(find.text('Allocation Buckets'), findsOneWidget);
    expect(find.text('Primary HDFC Salary'), findsOneWidget);

    // Toggle privacy mode
    final privacyButton = find.byTooltip('Toggle Privacy Mode');
    expect(privacyButton, findsOneWidget);

    await tester.tap(privacyButton);
    await tester.pumpAndSettle();

    // Verify balances masked
    expect(find.text('••••••••'), findsOneWidget);
  });
}
