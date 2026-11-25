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

  testWidgets('a screen opened on top is covered when the app relocks', (
    tester,
  ) async {
    var allow = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockEnabledProvider.overrideWith((ref) => true),
          authenticatorProvider.overrideWithValue((_) async => allow),
        ],
        child: MaterialApp(
          // As in RiveroApp: the gate wraps the navigator.
          builder: (context, child) =>
              AppLockGate(relockAfter: Duration.zero, child: child!),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('account page')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('account page'), findsOneWidget);

    // Someone else reopens the app and cannot verify.
    allow = false;
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await tester.pumpAndSettle();
    expect(find.text('Rivero is locked'), findsOneWidget);
    expect(find.text('account page'), findsNothing);

    // The owner unlocks and starts again from the first screen.
    allow = true;
    await tester.tap(find.byKey(const ValueKey('unlock')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('account page'), findsNothing);
  });

  testWidgets('turning the lock on after verifying keeps the app open', (
    tester,
  ) async {
    late WidgetRef r;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatorProvider.overrideWithValue((_) async => false),
        ],
        child: MaterialApp(
          builder: (context, child) => AppLockGate(child: child!),
          home: Consumer(
            builder: (context, ref, _) {
              r = ref;
              return const Text('settings page');
            },
          ),
        ),
      ),
    );
    // What Settings does once the person is verified.
    r.read(appUnlockedProvider.notifier).state = true;
    r.read(appLockEnabledProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(find.text('settings page'), findsOneWidget);
    expect(find.text('Rivero is locked'), findsNothing);
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
