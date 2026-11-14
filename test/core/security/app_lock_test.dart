import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/security/app_lock.dart';

void main() {
  testWidgets('locked until verified; relocks after a long absence', (
    tester,
  ) async {
    var allow = false;
    var asked = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockEnabledProvider.overrideWith((ref) => true),
          authenticatorProvider.overrideWithValue((_) async {
            asked++;
            return allow;
          }),
        ],
        child: const MaterialApp(
          home: AppLockGate(
            relockAfter: Duration.zero,
            child: Text('secret money'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('secret money'), findsNothing);
    expect(find.text('Rivero is locked'), findsOneWidget);
    expect(asked, greaterThan(0)); // prompts by itself

    allow = true;
    await tester.tap(find.byKey(const ValueKey('unlock')));
    await tester.pump();
    expect(find.text('secret money'), findsOneWidget);

    // Leave the app and come back: locked again.
    allow = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('secret money'), findsNothing);
  });

  testWidgets('no lock screen when the setting is off', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AppLockGate(child: Text('open'))),
      ),
    );
    expect(find.text('open'), findsOneWidget);
  });
}
