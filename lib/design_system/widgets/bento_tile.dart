import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_card.dart';

/// Slice "Explore" style tile: small caps label over a bold value.
class BentoTile extends StatelessWidget {
  const BentoTile({
    required this.label,
    required this.value,
    super.key,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RiveroCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: RiveroTypography.labelSmall.copyWith(letterSpacing: 1.5),
          ),
          const SizedBox(height: RiveroSpacing.sm),
          Text(
            value,
            style: RiveroTypography.displayMedium.copyWith(fontSize: 22),
          ),
        ],
      ),
    );
  }
}
