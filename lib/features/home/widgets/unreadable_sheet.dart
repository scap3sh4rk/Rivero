import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/database/daos/ingestion_logs_dao.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Bank messages Rivero could not read. Shown so a real payment is never
/// lost silently: add it on the Log tab, or dismiss it.
class UnreadableSheet extends ConsumerWidget {
  const UnreadableSheet({super.key});

  /// The Log tab's index in the bottom bar.
  static const logTab = 3;

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RiveroColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const UnreadableSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(unreadableMessagesProvider).value ?? const [];
    Future<void> dismiss(String id) => ref
        .read(databaseProvider)
        .ingestionLogsDao
        .updateParseStatus(id, ParseStatus.ignored, failureReason: 'Dismissed');

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(RiveroSpacing.xl),
          children: [
            Text('Bank messages to check', style: RiveroTypography.titleLarge),
            const SizedBox(height: RiveroSpacing.xs),
            Text(
              "Ones Rivero couldn't read, and autopays that failed. If one "
              'is a real payment, add it on the Log tab.',
              style: RiveroTypography.bodySmall,
            ),
            const SizedBox(height: RiveroSpacing.lg),
            if (logs.isEmpty)
              Text(
                'Nothing left to check.',
                style: RiveroTypography.bodyMedium,
              ),
            for (final l in logs)
              Padding(
                key: ValueKey(l.id),
                padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
                child: RiveroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l.failureReason == IngestionLogsDao.autopayFailed ? 'Autopay failed · ' : ''}'
                        '${l.senderHeader ?? 'Message'} · '
                        '${DateFormat('d MMM, h:mm a').format(l.receivedAt)}',
                        style: RiveroTypography.bodySmall.copyWith(
                          color:
                              l.failureReason == IngestionLogsDao.autopayFailed
                              ? RiveroColors.warning
                              : null,
                        ),
                      ),
                      const SizedBox(height: RiveroSpacing.xs),
                      Text(
                        l.rawPayload,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: RiveroTypography.bodyMedium,
                      ),
                      const SizedBox(height: RiveroSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: ValueKey('dismiss-${l.id}'),
                              onPressed: () => dismiss(l.id),
                              style: OutlinedButton.styleFrom(
                                shape: const StadiumBorder(),
                              ),
                              child: const Text('Not a payment'),
                            ),
                          ),
                          const SizedBox(width: RiveroSpacing.sm),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                await dismiss(l.id);
                                ref
                                        .read(selectedNavIndexProvider.notifier)
                                        .state =
                                    logTab;
                                if (context.mounted) Navigator.pop(context);
                              },
                              style: FilledButton.styleFrom(
                                shape: const StadiumBorder(),
                              ),
                              child: const Text('Add it'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
