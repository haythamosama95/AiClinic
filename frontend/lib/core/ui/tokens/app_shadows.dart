import 'package:flutter/material.dart';

/// Theme-aware elevation shadows.
abstract final class AppShadows {
  static const List<BoxShadow> elevation0 = [];

  static const List<BoxShadow> elevation1Light = [
    BoxShadow(
      color: Color.fromRGBO(16, 21, 28, 0.06),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color.fromRGBO(16, 21, 28, 0.04),
      blurRadius: 1,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> elevation2Light = [
    BoxShadow(
      color: Color.fromRGBO(16, 21, 28, 0.10),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> elevation3Light = [
    BoxShadow(
      color: Color.fromRGBO(16, 21, 28, 0.16),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];

  static const List<BoxShadow> elevation1Dark = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.24),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.16),
      blurRadius: 1,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> elevation2Dark = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.45),
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> elevation3Dark = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.55),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];

  static List<BoxShadow> forLevel(int level, Brightness brightness) {
    return switch (level) {
      0 => elevation0,
      1 => brightness == Brightness.dark ? elevation1Dark : elevation1Light,
      2 => brightness == Brightness.dark ? elevation2Dark : elevation2Light,
      3 => brightness == Brightness.dark ? elevation3Dark : elevation3Light,
      _ => elevation0,
    };
  }

  static List<BoxShadow> forContext(BuildContext context, int level) {
    return forLevel(level, Theme.of(context).brightness);
  }
}
