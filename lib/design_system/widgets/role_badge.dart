import 'package:flutter/material.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Pill badge displaying an AccountRole with associated accent colors.
class RoleBadge extends StatelessWidget {
  const RoleBadge({required this.role, super.key, this.isCompact = false});

  final AccountRole role;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final accent = role.accentColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? RiveroSpacing.xs : RiveroSpacing.sm,
        vertical: isCompact ? 2 : RiveroSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: RiveroRadii.borderFull,
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isCompact ? 5 : 6,
            height: isCompact ? 5 : 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          SizedBox(width: isCompact ? 4 : RiveroSpacing.xs),
          Text(
            role.displayName,
            style: isCompact
                ? RiveroTypography.labelSmall.copyWith(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  )
                : RiveroTypography.labelSmall.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
          ),
        ],
      ),
    );
  }
}
