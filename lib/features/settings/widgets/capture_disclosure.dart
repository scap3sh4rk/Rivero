import 'package:flutter/material.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// The prominent disclosure Google Play requires before asking for
/// notification access: what Rivero reads, what it keeps, and that nothing
/// leaves the phone. Opens Android's notification-access page only after the
/// user agrees.
Future<void> openCaptureAccess(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('capture-disclosure'),
      title: const Text('Let Rivero read payment notifications?'),
      content: SingleChildScrollView(
        child: Text(
          'To record payments for you, Rivero reads the notifications of your '
          'SMS app, bank apps and UPI apps, and payment notifications from '
          'other apps (a card or wallet app).\n\n'
          '• Only notifications that mention money are kept; everything else '
          'is ignored. Chat, social and email apps are never read.\n'
          '• One-time passwords are never stored.\n'
          '• Everything stays on this phone, encrypted. Nothing is sent to any '
          'server, and raw message text is deleted after 90 days.\n'
          '• Rivero never asks for SMS permission.\n\n'
          'You can turn this off any time in Android settings.',
          style: RiveroTypography.bodyMedium,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const ValueKey('capture-disclosure-agree'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Agree and continue'),
        ),
      ],
    ),
  );
  if (ok ?? false) await NotificationBridge.openSettings();
}
