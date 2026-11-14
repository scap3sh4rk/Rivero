import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/brand_wordmark.dart';

/// A short cinematic intro over the app on every cold start: the logo swells
/// out of the dark with a pulse of light, "Rivero" sweeps in, the tagline
/// settles, then the whole thing fades to reveal the app. Plays once per
/// launch and can be tapped away.
class LaunchOverlay extends StatefulWidget {
  const LaunchOverlay({required this.child, super.key});

  final Widget child;

  /// Off in tests.
  static bool enabled = true;
  static bool _played = false;

  @override
  State<LaunchOverlay> createState() => _LaunchOverlayState();
}

class _LaunchOverlayState extends State<LaunchOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late bool _show = LaunchOverlay.enabled && !LaunchOverlay._played;

  @override
  void initState() {
    super.initState();
    if (!_show) return;
    LaunchOverlay._played = true;
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _show = false);
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _t(double from, double to, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_c.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    if (!_show) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _show = false),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final fadeOut = 1 - _t(0.86, 1, Curves.easeIn);
              final logo = _t(0, 0.34, Curves.easeOutBack);
              final glow = math.sin(_t(0.05, 0.6, Curves.linear) * math.pi);
              final word = _t(0.3, 0.62);
              final tag = _t(0.58, 0.82);
              return Opacity(
                opacity: fadeOut,
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: 0.55 + 0.45 * logo,
                          child: Opacity(
                            opacity: logo.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF4EA3F8)
                                        .withValues(alpha: 0.55 * glow),
                                    blurRadius: 70 * glow + 6,
                                    spreadRadius: 6 * glow,
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/icon/logo.png',
                                width: 132,
                                height: 132,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Opacity(
                          opacity: word,
                          child: Transform.translate(
                            offset: Offset(0, 14 * (1 - word)),
                            child: const BrandWordmark(
                              fontSize: 46,
                              replay: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Opacity(
                          opacity: tag,
                          child: Text(
                            riveroTagline,
                            style: RiveroTypography.labelLarge.copyWith(
                              color: const Color(0xFFA1A1AA),
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
