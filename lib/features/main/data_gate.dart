import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// The data every tab reads. Waiting for it once here means no screen
/// flashes "nothing here" while the encrypted database opens; after that the
/// last values stay in place while updates stream in.
// ponytail: one gate for the core streams instead of a loading branch in
// every screen; add per-screen states only for data that loads on demand.
final _coreData = <ProviderListenable<AsyncValue<Object?>>>[
  activePhysicalAccountsProvider,
  allAllocationBucketsProvider,
  allTransactionsStreamProvider,
  allMandatesProvider,
  duesProvider,
];

/// Shows [child] once the core data has loaded; a calm loading view before
/// that, and a plain-language error with Retry if it cannot be read.
class DataGate extends ConsumerWidget {
  const DataGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = [for (final p in _coreData) ref.watch(p)];
    final failed = states.where((s) => s.hasError && !s.hasValue).firstOrNull;
    if (failed != null) {
      return _Message(
        key: const ValueKey('data-error'),
        icon: Icons.error_outline_rounded,
        title: 'Rivero could not read your data',
        body:
            'Nothing was changed or lost. Try again; if it keeps happening, '
            'restart the phone and open Rivero again.',
        action: FilledButton(
          key: const ValueKey('data-retry'),
          onPressed: () {
            ref
              ..invalidate(activePhysicalAccountsProvider)
              ..invalidate(allAllocationBucketsProvider)
              ..invalidate(allTransactionsStreamProvider)
              ..invalidate(allMandatesProvider)
              ..invalidate(duesProvider);
          },
          style: FilledButton.styleFrom(shape: const StadiumBorder()),
          child: const Text('Try again'),
        ),
      );
    }
    if (states.any((s) => !s.hasValue)) {
      return const _Message(
        key: ValueKey('data-loading'),
        icon: null,
        title: 'Opening your data',
        body: 'Unlocking the encrypted database on this phone.',
      );
    }
    return child;
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final IconData? icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RiveroColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(RiveroSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon == null)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  Icon(icon, size: 40, color: RiveroColors.textSecondary),
                const SizedBox(height: RiveroSpacing.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: RiveroTypography.titleMedium,
                ),
                const SizedBox(height: RiveroSpacing.sm),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: RiveroTypography.bodySmall,
                ),
                if (action != null) ...[
                  const SizedBox(height: RiveroSpacing.xl),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
