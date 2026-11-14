import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/daos/ingestion_logs_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/core/ingestion/trai_dlt_validator.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// What Rivero did with each notification it received: recorded, ignored
/// (and why), or not understood. Answers "why didn't my payment show up?".
class CaptureLogScreen extends ConsumerStatefulWidget {
  const CaptureLogScreen({super.key});

  @override
  ConsumerState<CaptureLogScreen> createState() => _CaptureLogScreenState();

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const CaptureLogScreen()));

  static String source(RawIngestionLog l) {
    final h = l.senderHeader;
    if (h == null) return 'Unknown source';
    return TraiDltValidator.knownPaymentPackages[h] ?? h;
  }

  static (String, Color) status(RawIngestionLog l) {
    switch (l.parseStatus) {
      case ParseStatus.parsed:
        return ('Recorded', RiveroColors.success);
      case ParseStatus.ignored:
        final why = (l.failureReason ?? '').replaceFirst(
          'Not a transaction: ',
          '',
        );
        return (
          switch (why) {
            'otp' => 'Ignored: one-time password',
            'preDebit' => 'Ignored: pre-debit reminder',
            'statementDue' => 'Ignored: card statement notice',
            'Dismissed' => 'Dismissed by you',
            '' => 'Ignored',
            _ => 'Ignored: $why',
          },
          RiveroColors.textSecondary,
        );
      case ParseStatus.failed:
        return (
          l.failureReason == IngestionLogsDao.autopayFailed
              ? 'Autopay failed'
              : l.failureReason == IngestionLogsDao.unreadable
              ? "Couldn't read this message"
              : (l.failureReason ?? 'Not recorded'),
          RiveroColors.warning,
        );
      case ParseStatus.quarantined:
        return ('Needs a look', RiveroColors.warning);
    }
  }
}

class _CaptureLogScreenState extends ConsumerState<CaptureLogScreen> {
  Map<String, dynamic> _diag = const {};
  bool? _listening;

  @override
  void initState() {
    super.initState();
    NotificationBridge.diagnostics().then((d) {
      if (mounted) setState(() => _diag = d);
    });
    NotificationBridge.isEnabled().then((on) {
      if (mounted) setState(() => _listening = on);
    });
  }

  Widget _diagCard() {
    if (!NotificationBridge.supported) return const SizedBox.shrink();
    final queued = (_diag['queued'] as int?) ?? 0;
    final noMoney = (_diag['noMoney'] as int?) ?? 0;
    final noText = (_diag['noText'] as int?) ?? 0;
    final last = _diag['lastPackage'] as String?;
    final lastTime = (_diag['lastTime'] as int?) ?? 0;
    final access = _listening == null
        ? 'checking'
        : _listening!
        ? 'on'
        : 'OFF (turn it on in Settings, Capture)';
    final heard =
        'Heard from your payment and bank apps: $queued with money in '
        'them, $noMoney without, $noText with hidden text.';
    final lastLine = last != null && lastTime > 0
        ? 'Last heard from ${TraiDltValidator.knownPaymentPackages[last] ?? last} at '
              '${DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(lastTime))}.'
        : null;
    const hiddenHint =
        'Some notifications had hidden text. In your phone settings, set '
        'notifications to show content (not "hide sensitive content") for '
        'your messages and UPI apps.';
    final lines = <String>['Notification access: $access', heard];
    if (lastLine != null) lines.add(lastLine);
    if (noText > 0) lines.add(hiddenHint);

    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.lg),
      child: RiveroCard(
        key: const ValueKey('capture-diagnostics'),
        child: Text(lines.join('\n\n'), style: RiveroTypography.bodySmall),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(recentCaptureLogsProvider).value ?? const [];
    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Recent captures',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RiveroSpacing.xl,
          0,
          RiveroSpacing.xl,
          RiveroSpacing.huge,
        ),
        children: [
          Text(
            'Every bank, UPI or SMS notification Rivero received, and what it '
            'did with it. Notifications that are not about money are never '
            'kept, so they do not appear here.',
            style: RiveroTypography.bodySmall,
          ),
          const SizedBox(height: RiveroSpacing.lg),
          _diagCard(),
          if (logs.isEmpty)
            RiveroCard(
              key: const ValueKey('no-captures'),
              child: Text(
                'Nothing received yet. Check that notification access is on '
                '(Settings, Capture), pick your UPI app, then use "Send a '
                'test notification".',
                style: RiveroTypography.bodyMedium,
              ),
            ),
          for (final l in logs)
            Padding(
              key: ValueKey('capture-${l.id}'),
              padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
              child: RiveroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${CaptureLogScreen.source(l)} · '
                            '${DateFormat('d MMM, h:mm a').format(l.receivedAt)}',
                            style: RiveroTypography.bodySmall,
                          ),
                        ),
                        Text(
                          CaptureLogScreen.status(l).$1,
                          style: RiveroTypography.labelLarge.copyWith(
                            color: CaptureLogScreen.status(l).$2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: RiveroSpacing.xs),
                    Text(
                      l.rawPayload,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: RiveroTypography.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
