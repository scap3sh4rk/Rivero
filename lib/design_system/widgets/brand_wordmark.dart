import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// "Rivero" revealed left to right with a light sweep across it, in the
/// palette's blues. Plays once per app launch (not on every visit to Home).
/// The app's tagline, shown on the first-run screen.
const riveroTagline = 'Your Money - In Flow';

class BrandWordmark extends StatefulWidget {
  const BrandWordmark({super.key, this.fontSize = 30});

  final double fontSize;

  /// Reset by tests.
  static bool played = false;

  @override
  State<BrandWordmark> createState() => _BrandWordmarkState();
}

class _BrandWordmarkState extends State<BrandWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (BrandWordmark.played) {
      _c.value = 1;
    } else {
      BrandWordmark.played = true;
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = RiveroTypography.displayLarge.copyWith(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: Colors.white,
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final reveal = Curves.easeOutCubic.transform(
          (_c.value / 0.75).clamp(0.0, 1.0),
        );
        // A bright band travels across the word once the reveal is going.
        final sweep = Curves.easeInOut.transform(
          ((_c.value - 0.25) / 0.75).clamp(0.0, 1.0),
        );
        final deep = RiveroColors.isLight
            ? const Color(0xFF0B3D91)
            : const Color(0xFF2F7FE0);
        return ClipRect(
          clipper: _LeftToRight(reveal),
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => LinearGradient(
              colors: [
                deep,
                RiveroColors.accent,
                const Color(0xFF9BD3FF),
                RiveroColors.accent,
                deep,
              ],
              stops: [
                0,
                (sweep - 0.2).clamp(0.0, 1.0) * 0.8 + 0.1,
                (sweep * 0.8 + 0.1).clamp(0.0, 1.0),
                (sweep + 0.2).clamp(0.0, 1.0) * 0.8 + 0.1,
                1,
              ],
            ).createShader(r),
            child: Text('Rivero', style: style),
          ),
        );
      },
    );
  }
}

class _LeftToRight extends CustomClipper<Rect> {
  const _LeftToRight(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftToRight old) => old.fraction != fraction;
}
