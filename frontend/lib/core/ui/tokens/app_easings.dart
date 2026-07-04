import 'package:flutter/material.dart';

/// Theme-independent easing curves.
abstract final class AppEasings {
  static const Cubic standard = Cubic(0.2, 0, 0, 1);
  static const Cubic out = Cubic(0.16, 1, 0.3, 1);
  static const Cubic inCurve = Cubic(0.4, 0, 1, 1);
  static const Cubic inOut = Cubic(0.65, 0, 0.35, 1);
  static const Cubic emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve linear = Curves.linear;
}
