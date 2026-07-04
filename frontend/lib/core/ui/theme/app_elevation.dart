import 'package:flutter/material.dart';

/// Theme-aware elevation shadows matching `--elevation-*` tokens.
@immutable
class AppElevation extends ThemeExtension<AppElevation> {
  const AppElevation({
    required this.level0,
    required this.level1,
    required this.level2,
    required this.level3,
  });

  final List<BoxShadow> level0;
  final List<BoxShadow> level1;
  final List<BoxShadow> level2;
  final List<BoxShadow> level3;

  static const AppElevation light = AppElevation(
    level0: [],
    level1: [
      BoxShadow(color: Color(0x0F10151C), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x0A10151C), offset: Offset(0, 1), blurRadius: 1),
    ],
    level2: [
      BoxShadow(color: Color(0x1A10151C), offset: Offset(0, 4), blurRadius: 12),
    ],
    level3: [
      BoxShadow(
        color: Color(0x2910151C),
        offset: Offset(0, 12),
        blurRadius: 32,
      ),
    ],
  );

  static const AppElevation dark = AppElevation(
    level0: [],
    level1: [
      BoxShadow(color: Color(0x3D000000), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x29000000), offset: Offset(0, 1), blurRadius: 1),
    ],
    level2: [
      BoxShadow(color: Color(0x73000000), offset: Offset(0, 4), blurRadius: 14),
    ],
    level3: [
      BoxShadow(
        color: Color(0x8C000000),
        offset: Offset(0, 12),
        blurRadius: 32,
      ),
    ],
  );

  List<BoxShadow> level(int index) => switch (index) {
    0 => level0,
    1 => level1,
    2 => level2,
    3 => level3,
    _ => level0,
  };

  @override
  AppElevation copyWith({
    List<BoxShadow>? level0,
    List<BoxShadow>? level1,
    List<BoxShadow>? level2,
    List<BoxShadow>? level3,
  }) {
    return AppElevation(
      level0: level0 ?? this.level0,
      level1: level1 ?? this.level1,
      level2: level2 ?? this.level2,
      level3: level3 ?? this.level3,
    );
  }

  @override
  AppElevation lerp(ThemeExtension<AppElevation>? other, double t) {
    if (other is! AppElevation) return this;
    return AppElevation(
      level0: BoxShadow.lerpList(level0, other.level0, t) ?? level0,
      level1: BoxShadow.lerpList(level1, other.level1, t) ?? level1,
      level2: BoxShadow.lerpList(level2, other.level2, t) ?? level2,
      level3: BoxShadow.lerpList(level3, other.level3, t) ?? level3,
    );
  }
}
