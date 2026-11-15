import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';

/// Hiding amounts: one global switch (the eye at the top of every page) and
/// one per account. The per-account eye wins: showing one account while
/// everything is hidden turns the global switch off and keeps every other
/// account hidden, so only that one is revealed.

/// Whether [accountId]'s balance is hidden right now.
bool accountMasked(WidgetRef ref, String accountId) =>
    ref.watch(privacyModeProvider) ||
    ref.watch(hiddenBalancesProvider).contains(accountId);

/// The per-account eye.
void toggleAccountMask(WidgetRef ref, String accountId) {
  final hidden = ref.read(hiddenBalancesProvider.notifier);
  if (ref.read(privacyModeProvider)) {
    final all = ref.read(activePhysicalAccountsProvider).value ?? const [];
    hidden.state = {
      for (final a in all)
        if (a.id != accountId) a.id,
    };
    ref.read(privacyModeProvider.notifier).state = false;
    return;
  }
  hidden.state = hidden.state.contains(accountId)
      ? ({...hidden.state}..remove(accountId))
      : {...hidden.state, accountId};
}

/// The global eye and the Settings switch. Showing everything also clears
/// the per-account choices, so "show" always means every amount.
void setHideAll(WidgetRef ref, {required bool hide}) {
  ref.read(privacyModeProvider.notifier).state = hide;
  if (!hide) ref.read(hiddenBalancesProvider.notifier).state = const {};
}
