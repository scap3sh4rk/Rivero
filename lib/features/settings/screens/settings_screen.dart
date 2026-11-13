import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';
import 'package:rivero/features/mandates/mandates_screen.dart';

/// Settings & Customization screen for paycycle configuration, custom account types,
/// credit score alert thresholds, privacy toggles, and data controls.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPrivacy = ref.watch(privacyModeProvider);
    final salaryDay = ref.watch(userSalaryDayProvider);
    final paycycle = ref.watch(currentPaycycleProvider);
    final customTypes = ref.watch(customAccountTypesProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: const RiveroAppBar(
        title: 'Settings',
        subtitle: 'Preferences & System Customization',
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: RiveroSpacing.lg,
          vertical: RiveroSpacing.md,
        ),
        children: [
          _buildSectionHeader('APPEARANCE'),
          RiveroCard(
            padding: const EdgeInsets.all(RiveroSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<AppThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.system,
                    label: Text('Auto'),
                    icon: Icon(Icons.brightness_auto_outlined),
                  ),
                ],
                selected: {ref.watch(themeModeProvider)},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).state = s.first,
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: RiveroSpacing.xs,
            ),
            title: const Text('Open on quick log'),
            subtitle: const Text('Start on the keypad instead of Home'),
            value: ref.watch(openOnLogProvider),
            onChanged: (v) => ref.read(openOnLogProvider.notifier).state = v,
          ),
          const SizedBox(height: RiveroSpacing.lg),

          _buildSectionHeader('AUTOMATION'),
          RiveroCard(
            padding: const EdgeInsets.all(RiveroSpacing.md),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.autorenew_rounded),
                    title: const Text('Autopay & mandates'),
                    subtitle: Text(
                      'Track and cancel recurring debits',
                      style: RiveroTypography.bodySmall,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => MandatesScreen.open(context),
                  ),
                  Divider(color: RiveroColors.borderSubtle),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.credit_card_outlined),
                    title: const Text('Reserve credit card spend'),
                    subtitle: Text(
                      'Keep money aside for unpaid card bills in Safe-to-Spend',
                      style: RiveroTypography.bodySmall,
                    ),
                    value: ref.watch(reserveCreditCardsProvider),
                    onChanged: (v) =>
                        ref.read(reserveCreditCardsProvider.notifier).state = v,
                  ),
                  if (NotificationBridge.supported) ...[
                    Divider(color: RiveroColors.borderSubtle),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: const Text('Auto-capture from notifications'),
                      subtitle: Text(
                        'Grant notification access so spends log themselves',
                        style: RiveroTypography.bodySmall,
                      ),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: NotificationBridge.openSettings,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: RiveroSpacing.lg),

          // 1. Paycycle & Salary Configuration
          _buildSectionHeader('PAYCYCLE CONFIGURATION'),
          RiveroCard(
            padding: const EdgeInsets.all(RiveroSpacing.md),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.calendar_month_rounded,
                  color: RiveroColors.salaryAccent,
                ),
                title: Text(
                  'Salary Credit Day',
                  style: RiveroTypography.titleMedium.copyWith(fontSize: 15),
                ),
                subtitle: Text(
                  'Cycle: Day $salaryDay of month (${paycycle.daysRemaining} days left)',
                  style: RiveroTypography.bodySmall,
                ),
                trailing: DropdownButton<int>(
                  value: salaryDay,
                  dropdownColor: RiveroColors.surfaceElevated,
                  style: RiveroTypography.bodyLarge,
                  underline: const SizedBox.shrink(),
                  items: List.generate(31, (i) => i + 1).map((day) {
                    return DropdownMenuItem(
                      value: day,
                      child: Text('Day $day'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(userSalaryDayProvider.notifier).state = val;
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: RiveroSpacing.lg),

          // 2. Custom Account Types Manager
          _buildSectionHeader(
            'CUSTOM ACCOUNT TYPES (${customTypes.length}/100)',
          ),
          RiveroCard(
            padding: const EdgeInsets.all(RiveroSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Account Types',
                      style: RiveroTypography.titleMedium.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Type'),
                      style: TextButton.styleFrom(
                        foregroundColor: RiveroColors.salaryAccent,
                      ),
                      onPressed: () => _promptAddAccountType(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: RiveroSpacing.xs),
                Text(
                  'Customize your account types across up to 100 personal financial classifications.',
                  style: RiveroTypography.bodySmall.copyWith(
                    color: RiveroColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: RiveroSpacing.md),
                Wrap(
                  spacing: RiveroSpacing.xs,
                  runSpacing: RiveroSpacing.xs,
                  children: customTypes.map((type) {
                    final isCustom = !StandardAccountTypes.defaultList.contains(
                      type,
                    );
                    return Chip(
                      avatar: Icon(
                        StandardAccountTypes.getIcon(type),
                        size: 14,
                        color: RiveroColors.textSecondary,
                      ),
                      label: Text(type),
                      labelStyle: RiveroTypography.labelSmall.copyWith(
                        fontSize: 11,
                      ),
                      backgroundColor: RiveroColors.surfaceElevated,
                      deleteIcon: isCustom
                          ? const Icon(Icons.close, size: 14)
                          : null,
                      onDeleted: isCustom
                          ? () {
                              ref
                                  .read(customAccountTypesProvider.notifier)
                                  .state = customTypes
                                  .where((t) => t != type)
                                  .toList();
                            }
                          : null,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: RiveroSpacing.lg),

          // 3. Credit Line Score Rules
          _buildSectionHeader('CREDIT SCORE MONITORING'),
          RiveroCard(
            padding: const EdgeInsets.all(RiveroSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Credit Utilization Thresholds',
                  style: RiveroTypography.titleMedium.copyWith(fontSize: 15),
                ),
                const SizedBox(height: RiveroSpacing.xs),
                Text(
                  'Rivero continuously evaluates your credit cards against industry score benchmarks:',
                  style: RiveroTypography.bodySmall,
                ),
                const SizedBox(height: RiveroSpacing.md),
                _buildRuleItem(
                  color: RiveroColors.investmentAccent,
                  title: '<= 10% Utilization — Optimal & Safe',
                  description:
                      'Keeps credit score in the excellent tier (750+).',
                ),
                const SizedBox(height: RiveroSpacing.sm),
                _buildRuleItem(
                  color: RiveroColors.salaryAccent,
                  title: '10% – 30% Utilization — Moderate Usage',
                  description:
                      'Standard usage threshold before penalties trigger.',
                ),
                const SizedBox(height: RiveroSpacing.sm),
                _buildRuleItem(
                  color: RiveroColors.danger,
                  title: '> 30% Utilization — Negatively Affects Score',
                  description:
                      'Lenders view high utilization as credit dependency.',
                ),
              ],
            ),
          ),
          const SizedBox(height: RiveroSpacing.lg),

          // 4. Privacy & Display
          _buildSectionHeader('PRIVACY & SECURITY'),
          RiveroCard(
            padding: const EdgeInsets.all(RiveroSpacing.md),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      Icons.visibility_off_outlined,
                      color: RiveroColors.textSecondary,
                    ),
                    title: Text(
                      'Privacy Mode (Mask Balances)',
                      style: RiveroTypography.titleMedium.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      'Hides exact monetary amounts with •••••••• in public spaces',
                      style: RiveroTypography.bodySmall,
                    ),
                    value: isPrivacy,
                    activeColor: RiveroColors.investmentAccent,
                    onChanged: (val) {
                      ref.read(privacyModeProvider.notifier).state = val;
                    },
                  ),
                  Divider(color: RiveroColors.borderSubtle),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.lock_outline_rounded,
                      color: RiveroColors.investmentAccent,
                    ),
                    title: Text(
                      'Encrypted on-device storage',
                      style: RiveroTypography.titleMedium.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      'AES-256 database, key in the system keystore · No cloud sync · No SMS permission',
                      style: RiveroTypography.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: RiveroSpacing.lg),

          if (kDebugMode) ...[
            // 5. Debug-only demo data
            _buildSectionHeader('DEBUG'),
            RiveroCard(
              padding: const EdgeInsets.all(RiveroSpacing.md),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.restore_rounded,
                    color: RiveroColors.salaryAccent,
                  ),
                  title: Text(
                    'Load demo data',
                    style: RiveroTypography.titleMedium.copyWith(fontSize: 15),
                  ),
                  subtitle: Text(
                    'Replaces everything with sample accounts and transactions (debug builds only)',
                    style: RiveroTypography.bodySmall,
                  ),
                  onTap: () => _confirmReset(context, ref),
                ),
              ),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RiveroSpacing.xs),
      child: Text(
        title,
        style: RiveroTypography.labelSmall.copyWith(
          letterSpacing: 1.5,
          color: RiveroColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildRuleItem({
    required Color color,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: RiveroSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: RiveroTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: color,
                ),
              ),
              Text(
                description,
                style: RiveroTypography.bodySmall.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _promptAddAccountType(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final textController = TextEditingController();
    final newType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: RiveroColors.surfaceElevated,
        title: Text('New Account Type', style: RiveroTypography.titleMedium),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: RiveroTypography.bodyLarge,
          decoration: const InputDecoration(
            hintText: 'e.g. PPF Account, Forex Card, Chit Fund',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final trimmed = textController.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newType != null && newType.isNotEmpty) {
      final current = ref.read(customAccountTypesProvider);
      if (current.length >= 100) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Maximum 100 custom account types reached.'),
            ),
          );
        }
        return;
      }
      if (!current.contains(newType)) {
        ref.read(customAccountTypesProvider.notifier).state = [
          ...current,
          newType,
        ];
      }
    }
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: RiveroColors.surfaceElevated,
        title: Text(
          'Reset Data to Sample Baseline?',
          style: RiveroTypography.titleMedium,
        ),
        content: Text(
          'This will re-initialize default physical accounts, virtual buckets, recurring mandates, and swiper transactions.',
          style: RiveroTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: RiveroColors.salaryAccent,
              foregroundColor: RiveroColors.background,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final seeder = ref.read(databaseSeederProvider);
      await seeder.forceReseed();
      await ref.read(settingsSyncProvider).load();
      ref
        ..invalidate(allAllocationBucketsProvider)
        ..invalidate(activePhysicalAccountsProvider)
        ..invalidate(pendingReviewTransactionsProvider)
        ..invalidate(recentTransactionsProvider)
        ..invalidate(allTransactionsStreamProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Financial profile successfully reset!'),
            backgroundColor: RiveroColors.investmentAccent,
          ),
        );
      }
    }
  }
}
