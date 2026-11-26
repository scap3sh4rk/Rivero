import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';

/// How long Undo is offered.
const undoWindow = Duration(seconds: 5);

/// Deletes entry [id] with an Undo: it disappears at once, and is deleted
/// (balances and budget corrected) only when the Undo is gone without being
/// tapped. Safe if the app closes meanwhile: nothing was deleted yet.
/// [context] may be closed right after (a sheet): the app's own messenger
/// and providers are used.
void deleteWithUndo(BuildContext context, String id) {
  final container = ProviderScope.containerOf(context);
  final messenger = ScaffoldMessenger.of(context);
  final hidden = container.read(pendingRemovalsProvider.notifier);
  hidden.state = {...hidden.state, id};
  messenger.hideCurrentSnackBar();
  messenger
      .showSnackBar(
        SnackBar(
          key: ValueKey('undo-delete-$id'),
          content: const Text('Entry deleted'),
          duration: undoWindow,
          // Snackbars with an action stay until dismissed unless told not to.
          persist: false,
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ),
      )
      .closed
      .then((reason) async {
        if (reason != SnackBarClosedReason.action) {
          await container.read(ledgerServiceProvider).removeWithPlanPartner(id);
        }
        hidden.state = {...hidden.state}..remove(id);
      });
}

/// Ignores waiting entry [id] with an Undo that brings it back to review.
Future<void> ignoreWithUndo(BuildContext context, String id) async {
  final container = ProviderScope.containerOf(context);
  final messenger = ScaffoldMessenger.of(context);
  await container.read(ledgerServiceProvider).ignore(id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: ValueKey('undo-ignore-$id'),
        content: const Text('Ignored'),
        duration: undoWindow,
        // Snackbars with an action stay until dismissed unless told not to.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => container.read(ledgerServiceProvider).unignore(id),
        ),
      ),
    );
}
