import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Top application bar styled according to Rivero aesthetic.
class RiveroAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RiveroAppBar({
    required this.title,
    super.key,
    this.subtitle,
    this.leading,
    this.actions,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight +
        (bottom?.preferredSize.height ?? 0) +
        (subtitle != null ? 14 : 0),
  );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: RiveroColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: leading,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: RiveroTypography.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: RiveroTypography.bodySmall),
          ],
        ],
      ),
      actions: actions,
      bottom:
          bottom ??
          PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(
              color: RiveroColors.borderSubtle,
              height: 1,
              thickness: 1,
            ),
          ),
    );
  }
}
