import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/design_system/eager_page_physics.dart';

void main() {
  int t(double page, double v, {int settled = 2}) =>
      EagerPagePhysics.targetPage(
        page: page,
        velocity: v,
        settled: settled,
        lastPage: 4,
      );

  test('a short drag is enough to move one page either way', () {
    expect(t(2.15, 0), 3);
    expect(t(1.85, 0), 1);
  });

  test('tiny drags snap back', () {
    expect(t(2.05, 0), 2);
    expect(t(1.95, 0), 2);
  });

  test('a flick moves in its direction; edges are clamped', () {
    expect(t(2.02, 400), 3);
    expect(t(1.98, -400), 1);
    expect(t(4.1, 500, settled: 4), 4);
    expect(t(-0.1, -500, settled: 0), 0);
  });
}
