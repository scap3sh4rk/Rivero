import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/security/app_lock.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';
import 'package:rivero/features/mandates/mandates_screen.dart';
import 'package:rivero/features/settings/screens/account_types_screen.dart';
import 'package:rivero/features/settings/screens/categories_screen.dart';

/// Settings as short rows: one line each, details one tap deeper.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const Map<AppThemeMode, String> _themeLabels = {
    AppThemeMode.dark: 'Dark',
    AppThemeMode.light: 'Light',
    AppThemeMode.system: 'Match phone',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salaryDay = ref.watch(userSalaryDayProvider);
    final paycycle = ref.watch(currentPaycycleProvider);
    final theme = ref.watch(themeModeProvider);
    final types = ref.watch(customAccountTypesProvider);

    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        title: 'Settings',
        showProfile: false,
        leading: Navigator.of(context).canPop()
            ? BackButton(onPressed: () => Navigator.of(context).pop())
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: RiveroSpacing.huge),
        children: [
          const _Header('General'),
          _Row(
            icon: Icons.event_outlined,
            title: 'Pay day',
            subtitle:
                'Day $salaryDay · ${paycycle.daysRemaining} days to next pay',
            onTap: () => _pickPayDay(context, ref, salaryDay),
          ),
          _Row(
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: _themeLabels[theme],
            onTap: () => _pickTheme(context, ref, theme),
          ),
          _Row(
            icon: Icons.dialpad_rounded,
            title: 'Open on quick log',
            trailing: Switch(
              value: ref.watch(openOnLogProvider),
              onChanged: (v) => ref.read(openOnLogProvider.notifier).state = v,
            ),
          ),
          const _Header('Money'),
          _Row(
            icon: Icons.autorenew_rounded,
            title: 'Autopay',
            subtitle: 'Recurring debits across all banks',
            onTap: () => MandatesScreen.open(context),
          ),
          _Row(
            icon: Icons.credit_card_outlined,
            title: 'Keep money aside for card bills',
            subtitle: 'Unpaid card spend lowers Safe to spend',
            trailing: Switch(
              value: ref.watch(reserveCreditCardsProvider),
              onChanged: (v) =>
                  ref.read(reserveCreditCardsProvider.notifier).state = v,
            ),
          ),
          _Row(
            icon: Icons.handshake_outlined,
            title: 'Count money owed to me',
            subtitle: 'Adds what friends owe you to Safe to spend',
            trailing: Switch(
              value: ref.watch(includePendingReimbursementsProvider),
              onChanged: (v) =>
                  ref
                          .read(includePendingReimbursementsProvider.notifier)
                          .state =
                      v,
            ),
          ),
          _Row(
            icon: Icons.sell_outlined,
            title: 'Categories',
            subtitle: 'Used by Log and Activity',
            onTap: () => CategoriesScreen.open(context),
          ),
          _Row(
            icon: Icons.category_outlined,
            title: 'Account types',
            subtitle: '${types.length}',
            onTap: () => AccountTypesScreen.open(context),
          ),
          if (NotificationBridge.supported) ...[
            const _Header('Capture'),
            const _CaptureRows(),
          ],
          const _Header('Privacy'),
          _Row(
            icon: Icons.visibility_off_outlined,
            title: 'Hide amounts',
            trailing: Switch(
              key: const ValueKey('privacy-switch'),
              value: ref.watch(privacyModeProvider),
              onChanged: (v) =>
                  ref.read(privacyModeProvider.notifier).state = v,
            ),
          ),
          _Row(
            icon: Icons.fingerprint_rounded,
            title: 'App lock',
            subtitle: 'Fingerprint, face or phone PIN to open',
            trailing: Switch(
              key: const ValueKey('app-lock-switch'),
              value: ref.watch(appLockEnabledProvider),
              onChanged: (v) => _setAppLock(context, ref, v),
            ),
          ),
          const _Row(
            icon: Icons.lock_outline_rounded,
            title: 'Encrypted on this phone',
            subtitle: 'No cloud, no SMS permission',
          ),
          const _Header('Developer'),
          _Row(
            icon: Icons.delete_forever_outlined,
            title: 'Delete all data',
            subtitle: 'Erases everything and starts setup again',
            onTap: () => _confirmWipe(context, ref),
          ),
          if (kDebugMode) ...[
            _Row(
              icon: Icons.science_outlined,
              title: 'Load demo data',
              subtitle: 'Replaces everything with sample data',
              onTap: () => _confirmReset(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setAppLock(BuildContext context, WidgetRef ref, bool on) async {
    // Verify the person first, both to turn it on and to turn it off.
    final ok = await ref.read(authenticatorProvider)(
      on ? 'Confirm to turn on app lock' : 'Confirm to turn off app lock',
    );
    if (ok) {
      ref.read(appLockEnabledProvider.notifier).state = on;
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not verify. Is a screen lock set on this phone?',
          ),
        ),
      );
    }
  }

  Future<void> _confirmWipe(BuildContext context, WidgetRef ref) async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Delete all data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Accounts, transactions, plans, autopays and settings are '
                'erased from this phone. This cannot be undone.',
              ),
              const SizedBox(height: RiveroSpacing.md),
              TextField(
                key: const ValueKey('wipe-confirm'),
                controller: typed,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Type DELETE'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: RiveroColors.danger,
              ),
              onPressed: typed.text.trim() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete everything'),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (ok != true || !context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await ref.read(databaseProvider).wipeAll();
    await ref.read(settingsSyncProvider).load(); // -> back to setup
  }

  Future<void> _pickPayDay(BuildContext context, WidgetRef ref, int current) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: RiveroColors.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RiveroSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pay day', style: RiveroTypography.titleLarge),
              const SizedBox(height: RiveroSpacing.lg),
              Wrap(
                spacing: RiveroSpacing.sm,
                runSpacing: RiveroSpacing.sm,
                children: [
                  for (var d = 1; d <= 31; d++)
                    ChoiceChip(
                      label: SizedBox(
                        width: 24,
                        child: Text('$d', textAlign: TextAlign.center),
                      ),
                      selected: d == current,
                      showCheckmark: false,
                      shape: const CircleBorder(),
                      onSelected: (_) {
                        ref.read(userSalaryDayProvider.notifier).state = d;
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref,
    AppThemeMode current,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: RiveroColors.surface,
      builder: (ctx) => SafeArea(
        child: RadioGroup<AppThemeMode>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) ref.read(themeModeProvider.notifier).state = v;
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in _themeLabels.entries)
                RadioListTile<AppThemeMode>(value: e.key, title: Text(e.value)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load demo data?'),
        content: const Text('This replaces all your data with samples.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(databaseSeederProvider).forceReseed();
    await ref.read(settingsSyncProvider).load();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Demo data loaded')));
    }
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      RiveroSpacing.xl,
      RiveroSpacing.xl,
      RiveroSpacing.xl,
      RiveroSpacing.xs,
    ),
    child: Text(
      text.toUpperCase(),
      style: RiveroTypography.labelSmall.copyWith(letterSpacing: 1.2),
    ),
  );
}

/// Slice-style settings row: round outlined icon, title, optional subtitle.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Inset so the rounded press highlight sits inside the screen edges.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.sm),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: RiveroSpacing.md,
          vertical: RiveroSpacing.xs,
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: RiveroColors.borderMedium),
          ),
          child: Icon(icon, size: 20, color: RiveroColors.textSecondary),
        ),
        title: Text(title, style: RiveroTypography.bodyLarge),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: RiveroTypography.bodySmall),
        trailing:
            trailing ??
            (onTap == null
                ? null
                : Icon(
                    Icons.chevron_right_rounded,
                    color: RiveroColors.textMuted,
                  )),
      ),
    );
  }
}

/// Notification access status + an end-to-end capture test.
class _CaptureRows extends ConsumerStatefulWidget {
  const _CaptureRows();

  @override
  ConsumerState<_CaptureRows> createState() => _CaptureRowsState();
}

class _CaptureRowsState extends ConsumerState<_CaptureRows>
    with WidgetsBindingObserver {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from the system settings page: re-check access.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final on = await NotificationBridge.isEnabled();
    if (mounted) setState(() => _enabled = on);
  }

  Future<void> _sendTest() async {
    final accounts = ref.read(activePhysicalAccountsProvider).value ?? const [];
    final mask = accounts.where((a) => !a.isLiability).firstOrNull?.accountMask;
    final status = await NotificationBridge.postTest(
      body: NotificationBridge.sampleMessage(
        mask: mask == null || mask.contains('•') ? '0000' : mask,
        now: DateTime.now(),
      ),
    );
    if (!mounted) return;
    final text = switch (status) {
      'posted' =>
        'Test sent. A ₹1 "rivero.test" entry should appear in Activity '
            'within a few seconds. You can delete it there.',
      'no_access' => 'Turn on notification access first.',
      'no_permission' => 'Allow Rivero to show notifications, then try again.',
      _ => 'Not available on this device.',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    if (status == 'no_access') await NotificationBridge.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Row(
          icon: Icons.notifications_active_outlined,
          title: 'Notification access',
          subtitle: switch (_enabled) {
            null => 'Checking…',
            true => 'On · spends log themselves',
            false => 'Off · tap to turn on',
          },
          onTap: NotificationBridge.openSettings,
        ),
        _Row(
          icon: Icons.send_outlined,
          title: 'Send a test notification',
          subtitle: 'Checks capture end to end with a ₹1 sample',
          onTap: _sendTest,
        ),
      ],
    );
  }
}
