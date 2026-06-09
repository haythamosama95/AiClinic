import 'package:flutter/material.dart';

import 'variants/app_theme_variant.dart';

/// Active design-system variant carried on [ThemeData].
@immutable
class AppThemeMeta extends ThemeExtension<AppThemeMeta> {
  const AppThemeMeta({required this.variant});

  final AppThemeVariant variant;

  @override
  AppThemeMeta copyWith({AppThemeVariant? variant}) {
    return AppThemeMeta(variant: variant ?? this.variant);
  }

  @override
  AppThemeMeta lerp(ThemeExtension<AppThemeMeta>? other, double t) {
    if (other is! AppThemeMeta) {
      return this;
    }

    return t < 0.5 ? this : other;
  }
}

/// Convenience accessor for [AppThemeMeta] from a [BuildContext].
extension AppThemeMetaContext on BuildContext {
  AppThemeVariant get appThemeVariant => Theme.of(this).extension<AppThemeMeta>()?.variant ?? AppThemeVariant.clinic;
}
