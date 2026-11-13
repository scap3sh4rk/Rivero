import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Reusable dark container card following Rivero design specifications.
/// Uses `#12121A` (surface) or `#1A1A26` (elevated) with subtle borders.
class RiveroCard extends StatefulWidget {
  const RiveroCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(RiveroSpacing.lg),
    this.margin,
    this.isElevated = false,
    this.borderColor,
    this.backgroundColor,
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool isElevated;
  final Color? borderColor;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  State<RiveroCard> createState() => _RiveroCardState();
}

class _RiveroCardState extends State<RiveroCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final effectiveBg =
        widget.backgroundColor ??
        (widget.isElevated
            ? RiveroColors.surfaceElevated
            : RiveroColors.surface);
    final effectiveBorder = widget.borderColor ?? RiveroColors.borderSubtle;
    final effectiveRadius = widget.borderRadius ?? RiveroRadii.borderMd;

    Widget cardContent = Container(
      margin: widget.margin,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: effectiveRadius,
        border: Border.all(color: effectiveBorder),
      ),
      child: widget.child,
    );

    if (widget.onTap != null) {
      cardContent = GestureDetector(
        onTapDown: (_) {
          HapticFeedback.selectionClick();
          setState(() => _isPressed = true);
        },
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}
