import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

enum RiveroButtonVariant { primary, secondary, danger, ghost }

enum RiveroButtonSize { small, medium, large }

/// Tactile button component adhering to Rivero design tokens.
class RiveroButton extends StatefulWidget {
  const RiveroButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = RiveroButtonVariant.primary,
    this.size = RiveroButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final RiveroButtonVariant variant;
  final RiveroButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;

  @override
  State<RiveroButton> createState() => _RiveroButtonState();
}

class _RiveroButtonState extends State<RiveroButton> {
  bool _isPressed = false;

  bool get _isEnabled => widget.onPressed != null && !widget.isLoading;

  Color get _backgroundColor {
    if (!_isEnabled) return RiveroColors.surfaceInteractive;
    switch (widget.variant) {
      case RiveroButtonVariant.primary:
        return RiveroColors.expenseAccent;
      case RiveroButtonVariant.secondary:
        return RiveroColors.surfaceElevated;
      case RiveroButtonVariant.danger:
        return RiveroColors.danger;
      case RiveroButtonVariant.ghost:
        return Colors.transparent;
    }
  }

  Color get _textColor {
    if (!_isEnabled) return RiveroColors.textDisabled;
    switch (widget.variant) {
      case RiveroButtonVariant.primary:
      case RiveroButtonVariant.danger:
        return Colors.white;
      case RiveroButtonVariant.secondary:
      case RiveroButtonVariant.ghost:
        return RiveroColors.textPrimary;
    }
  }

  BorderSide get _borderSide {
    if (!_isEnabled) return BorderSide.none;
    switch (widget.variant) {
      case RiveroButtonVariant.secondary:
        return BorderSide(color: RiveroColors.borderMedium);
      case RiveroButtonVariant.ghost:
      case RiveroButtonVariant.primary:
      case RiveroButtonVariant.danger:
        return BorderSide.none;
    }
  }

  EdgeInsets get _padding {
    switch (widget.size) {
      case RiveroButtonSize.small:
        return const EdgeInsets.symmetric(
          horizontal: RiveroSpacing.md,
          vertical: RiveroSpacing.xs,
        );
      case RiveroButtonSize.medium:
        return const EdgeInsets.symmetric(
          horizontal: RiveroSpacing.lg,
          vertical: RiveroSpacing.md,
        );
      case RiveroButtonSize.large:
        return const EdgeInsets.symmetric(
          horizontal: RiveroSpacing.xl,
          vertical: RiveroSpacing.lg,
        );
    }
  }

  TextStyle get _textStyle {
    switch (widget.size) {
      case RiveroButtonSize.small:
        return RiveroTypography.labelSmall.copyWith(
          color: _textColor,
          fontWeight: FontWeight.w600,
        );
      case RiveroButtonSize.medium:
      case RiveroButtonSize.large:
        return RiveroTypography.labelLarge.copyWith(
          color: _textColor,
          fontWeight: FontWeight.w600,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_textColor),
            ),
          ),
          const SizedBox(width: RiveroSpacing.sm),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: _textColor),
          const SizedBox(width: RiveroSpacing.sm),
        ],
        Text(widget.label, style: _textStyle),
      ],
    );

    return GestureDetector(
      onTapDown: _isEnabled
          ? (_) {
              HapticFeedback.lightImpact();
              setState(() => _isPressed = true);
            }
          : null,
      onTapUp: _isEnabled ? (_) => setState(() => _isPressed = false) : null,
      onTapCancel: _isEnabled ? () => setState(() => _isPressed = false) : null,
      onTap: _isEnabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutQuad,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: _padding,
          decoration: BoxDecoration(
            color: _backgroundColor,
            borderRadius: RiveroRadii.borderMd,
            border: Border.fromBorderSide(_borderSide),
          ),
          child: content,
        ),
      ),
    );
  }
}
