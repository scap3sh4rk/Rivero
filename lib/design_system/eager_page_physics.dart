import 'package:flutter/widgets.dart';

/// Page physics where a short drag (or a gentle flick) is enough to change
/// page, settling with a slightly underdamped spring for a soft bounce.
/// Use with `PageView(pageSnapping: false)` so this, not the default page
/// physics, decides the target page.
class EagerPagePhysics extends ScrollPhysics {
  const EagerPagePhysics({required this.settledPage, super.parent});

  /// The page the user started dragging from.
  final int Function() settledPage;

  /// Fraction of a page that commits to the next page.
  static const double dragThreshold = 0.12;

  /// px/s that counts as a deliberate flick.
  static const double flingVelocity = 250;

  @override
  EagerPagePhysics applyTo(ScrollPhysics? ancestor) =>
      EagerPagePhysics(settledPage: settledPage, parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: 0.72);

  /// Target page for a drag released at [page] (fractional) with [velocity].
  static int targetPage({
    required double page,
    required double velocity,
    required int settled,
    required int lastPage,
  }) {
    int target;
    if (velocity > flingVelocity) {
      target = page.ceil();
    } else if (velocity < -flingVelocity) {
      target = page.floor();
    } else if ((page - settled).abs() > dragThreshold) {
      target = page > settled ? settled + 1 : settled - 1;
    } else {
      target = settled;
    }
    return target.clamp(0, lastPage);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final viewport = position.viewportDimension;
    if (viewport <= 0) {
      return super.createBallisticSimulation(position, velocity);
    }
    final target = targetPage(
      page: position.pixels / viewport,
      velocity: velocity,
      settled: settledPage(),
      lastPage: (position.maxScrollExtent / viewport).round(),
    );
    final targetPixels = target * viewport;
    final tolerance = toleranceFor(position);
    if ((targetPixels - position.pixels).abs() < tolerance.distance) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      targetPixels,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
