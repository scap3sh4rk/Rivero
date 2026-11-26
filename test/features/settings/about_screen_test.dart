import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/features/settings/screens/about_screen.dart';

void main() {
  testWidgets('About shows the app, its links and the licenses page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AboutScreen())),
    );
    await tester.pump();
    expect(find.text('Rivero'), findsOneWidget);
    expect(find.byKey(const ValueKey('about-whats-new')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('about-licenses')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  test('the bundled fonts carry their licences', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFontLicenses();
    final names = <String>{};
    await for (final l in LicenseRegistry.licenses) {
      names.addAll(l.packages);
    }
    expect(names, containsAll(['Inter', 'Urbanist', 'JetBrains Mono']));
  });
}
