import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Slice "Explore" style tile: small caps label, a bold value and a short
/// caption. Every part is one line (long names end in "…"), so tiles side by
/// side are always the same size whatever they show.
class BentoTile extends StatelessWidget {
  const BentoTile({
    required this.label,
    required this.value,
    super.key,
    this.caption = '',
    this.leading,
    this.onTap,
  });

  final String label;
  final String value;

  /// A short second line (a date, a count). Kept even when empty so every
  /// tile has the same height.
  final String caption;

  /// Optional small icon before the label.
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RiveroCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: RiveroSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RiveroTypography.labelSmall.copyWith(
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: RiveroSpacing.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RiveroTypography.displayMedium.copyWith(fontSize: 22),
          ),
          Text(
            caption.isEmpty ? ' ' : caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RiveroTypography.bodySmall,
          ),
        ],
      ),
    );
  }
}
