import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/main/data_gate.dart';

void main() {
  Widget app(List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: DataGate(child: Text('home'))),
  );

  List<Override> loaded({Stream<List<PhysicalAccount>>? accounts}) => [
    activePhysicalAccountsProvider.overrideWith(
      (ref) => accounts ?? Stream.value(const []),
    ),
    allAllocationBucketsProvider.overrideWith((ref) => Stream.value(const [])),
    allTransactionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
    allMandatesProvider.overrideWith((ref) => Stream.value(const [])),
    duesProvider.overrideWith((ref) => Stream.value(const [])),
  ];

  testWidgets('a calm loading view until the data is there, then the app', (
    tester,
  ) async {
    final accounts = StreamController<List<PhysicalAccount>>();
    addTearDown(accounts.close);
    await tester.pumpWidget(app(loaded(accounts: accounts.stream)));
    await tester.pump();
    expect(find.text('Opening your data'), findsOneWidget);
    expect(find.text('home'), findsNothing);

    accounts.add(const []);
    await tester.pump();
    await tester.pump();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a read error is explained in plain words, with Try again', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(loaded(accounts: Stream.error(StateError('file is not a database')))),
    );
    await tester.pump();
    expect(find.text('Rivero could not read your data'), findsOneWidget);
    expect(find.byKey(const ValueKey('data-retry')), findsOneWidget);
    // The raw error never reaches the screen.
    expect(find.textContaining('not a database'), findsNothing);
  });
}
