import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/features/settings/widgets/capture_disclosure.dart';

void main() {
  testWidgets('notification access is explained before it is asked for', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openCaptureAccess(context),
            child: const Text('Turn on capture'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Turn on capture'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capture-disclosure')), findsOneWidget);
    expect(
      find.textContaining('never asks for SMS permission'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Nothing is sent to any server'),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capture-disclosure')), findsNothing);
  });
}
