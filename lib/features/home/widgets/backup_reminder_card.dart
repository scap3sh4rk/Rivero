import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/backup/auto_backup.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/backup/backup_screen.dart';

/// Shown on Home when there is data worth keeping and no backup for two
/// weeks (or ever): one tap to the Backup page.
class BackupReminderCard extends ConsumerWidget {
  const BackupReminderCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activePhysicalAccountsProvider).value;
    final last = ref.watch(lastBackupProvider);
    if (accounts == null || accounts.isEmpty || last.isLoading) {
      return const SizedBox.shrink();
    }
    final at = last.value;
    final stale =
        at == null || DateTime.now().difference(at) > AutoBackup.staleAfter;
    if (!stale) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.xl),
      child: RiveroCard(
        key: const ValueKey('backup-reminder'),
        onTap: () => BackupScreen.open(context),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: RiveroColors.warning),
            const SizedBox(width: RiveroSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    at == null ? 'Not backed up yet' : 'No backup for 2 weeks',
                    style: RiveroTypography.bodyLarge,
                  ),
                  Text(
                    'Turn on automatic encrypted backup so a lost phone '
                    'never loses your data.',
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
