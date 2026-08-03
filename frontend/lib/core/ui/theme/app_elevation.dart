import 'package:flutter/material.dart';

/// Shared shadow definitions for elevation levels 0–3.
abstract final class AppElevationShadows {
  static const level0 = <BoxShadow>[];

  static const level1Light = [
    BoxShadow(color: Color(0x0F10151C), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0A10151C), offset: Offset(0, 1), blurRadius: 1),
  ];

  static const level2Light = [BoxShadow(color: Color(0x1A10151C), offset: Offset(0, 4), blurRadius: 12)];

  static const level3Light = [BoxShadow(color: Color(0x2910151C), offset: Offset(0, 12), blurRadius: 32)];

  static const level1Dark = [
    BoxShadow(color: Color(0x3D000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x29000000), offset: Offset(0, 1), blurRadius: 1),
  ];

  static const level2Dark = [BoxShadow(color: Color(0x73000000), offset: Offset(0, 4), blurRadius: 14)];

  static const level3Dark = [BoxShadow(color: Color(0x8C000000), offset: Offset(0, 12), blurRadius: 32)];
}

/// Elevation shadow tokens (`02-tokens` §7).
@immutable
class AppElevation extends ThemeExtension<AppElevation> {
  const AppElevation({
    required this.shadows0,
    required this.shadows1,
    required this.shadows2,
    required this.shadows3,
  });

  /// Light-theme defaults for static decoration usage.
  static const level0 = AppElevationShadows.level0;
  static const level1 = AppElevationShadows.level1Light;
  static const level2 = AppElevationShadows.level2Light;
  static const level3 = AppElevationShadows.level3Light;

  final List<BoxShadow> shadows0;
  final List<BoxShadow> shadows1;
  final List<BoxShadow> shadows2;
  final List<BoxShadow> shadows3;

  static const light = AppElevation(
    shadows0: AppElevationShadows.level0,
    shadows1: AppElevationShadows.level1Light,
    shadows2: AppElevationShadows.level2Light,
    shadows3: AppElevationShadows.level3Light,
  );

  static const dark = AppElevation(
    shadows0: AppElevationShadows.level0,
    shadows1: AppElevationShadows.level1Dark,
    shadows2: AppElevationShadows.level2Dark,
    shadows3: AppElevationShadows.level3Dark,
  );

  static List<BoxShadow> forLevel(String token, {required Brightness brightness}) {
    final level = int.tryParse(token) ?? 0;
    final elevation = brightness == Brightness.dark ? dark : light;
    return elevation.shadowsFor(level);
  }

  List<BoxShadow> shadowsFor(int level) {
    return switch (level) {
      0 => shadows0,
      1 => shadows1,
      2 => shadows2,
      3 => shadows3,
      _ => shadows0,
    };
  }

  BoxDecoration decoration({
    required int level,
    Color? color,
    BorderRadius? borderRadius,
    BoxBorder? border,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: borderRadius,
      border: border,
      boxShadow: shadowsFor(level),
    );
  }

  @override
  AppElevation copyWith({
    List<BoxShadow>? shadows0,
    List<BoxShadow>? shadows1,
    List<BoxShadow>? shadows2,
    List<BoxShadow>? shadows3,
  }) {
    return AppElevation(
      shadows0: shadows0 ?? this.shadows0,
      shadows1: shadows1 ?? this.shadows1,
      shadows2: shadows2 ?? this.shadows2,
      shadows3: shadows3 ?? this.shadows3,
    );
  }

  @override
  AppElevation lerp(AppElevation? other, double t) {
    if (other is! AppElevation) {
      return this;
    }
    if (t < 0.5) {
      return this;
    }
    return other;
  }
}

extension AppElevationContext on BuildContext {
  AppElevation get appElevation => Theme.of(this).extension<AppElevation>()!;
}
