import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/features/home/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: RiveroApp()));
}

/// Root widget of the Rivero application.
class RiveroApp extends ConsumerStatefulWidget {
  const RiveroApp({super.key});

  @override
  ConsumerState<RiveroApp> createState() => _RiveroAppState();
}

class _RiveroAppState extends ConsumerState<RiveroApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(databaseSeederProvider).seedIfEmpty();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rivero',
      debugShowCheckedModeBanner: false,
      theme: RiveroTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
