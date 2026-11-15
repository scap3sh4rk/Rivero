import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/balance_mask.dart';
import 'package:rivero/features/settings/screens/settings_screen.dart';

/// Slice-style top bar: big left-aligned title, optional actions, and a round
/// profile button that opens Settings.
class RiveroAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RiveroAppBar({
    required this.title,
    super.key,
    this.titleWidget,
    this.subtitle,
    this.leading,
    this.actions,
    this.bottom,
    this.showProfile = true,
    this.showEye = true,
  });

  final String title;

  /// Replaces the plain title text (e.g. the animated wordmark).
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool showProfile;

  /// The eye that hides or shows every amount (on every page).
  final bool showEye;

  @override
  Size get preferredSize => Size.fromHeight(
    72 + (subtitle != null ? 14 : 0) + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: RiveroColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 72 + (subtitle != null ? 14 : 0),
      leading: leading,
      titleSpacing: leading == null ? RiveroSpacing.xl : 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          titleWidget ??
              Text(
                title,
                style: RiveroTypography.displayLarge.copyWith(fontSize: 30),
              ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: RiveroTypography.bodySmall),
          ],
        ],
      ),
      actions: [
        ...?actions,
        if (showEye) const _EyeButton(),
        if (showProfile)
          Padding(
            padding: const EdgeInsets.only(
              left: RiveroSpacing.xs,
              right: RiveroSpacing.lg,
            ),
            child: Tooltip(
              message: 'Profile & Settings',
              child: InkResponse(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: RiveroColors.surfaceInteractive,
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: RiveroColors.textPrimary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
      ],
      bottom: bottom,
    );
  }
}

/// Hides or shows every amount in the app. Same icon, same place, on every
/// page.
class _EyeButton extends ConsumerWidget {
  const _EyeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(privacyModeProvider);
    return IconButton(
      key: const ValueKey('toggle-balances'),
      tooltip: 'Toggle Privacy Mode',
      icon: Icon(
        hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: RiveroColors.textSecondary,
      ),
      onPressed: () => setHideAll(ref, hide: !hidden),
    );
  }
}
