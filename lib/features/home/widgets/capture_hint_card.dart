import 'package:flutter/material.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Android only: while notification access is off Rivero cannot see bank or
/// UPI payments, so Home says so and takes you straight to the switch.
class CaptureHintCard extends StatefulWidget {
  const CaptureHintCard({super.key});

  @override
  State<CaptureHintCard> createState() => _CaptureHintCardState();
}

class _CaptureHintCardState extends State<CaptureHintCard>
    with WidgetsBindingObserver {
  bool _off = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!NotificationBridge.supported) return;
    final on = await NotificationBridge.isEnabled();
    if (mounted) setState(() => _off = !on);
  }

  @override
  Widget build(BuildContext context) {
    if (!_off) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.xl),
      child: RiveroCard(
        key: const ValueKey('capture-hint'),
        onTap: NotificationBridge.openSettings,
        child: Row(
          children: [
            const Icon(
              Icons.notifications_off_outlined,
              color: RiveroColors.warning,
            ),
            const SizedBox(width: RiveroSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payments are not being captured',
                    style: RiveroTypography.bodyLarge,
                  ),
                  Text(
                    'Turn on notification access so bank and UPI payments '
                    'record themselves.',
                    style: RiveroTypography.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
