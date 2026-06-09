/// Named design-system variants. Each variant owns its own token files.
enum AppThemeVariant {
  /// Astro Vista palette (orange primary, blue secondary).
  clinic,

  /// Claude+ palette (terracotta primary, cream surfaces).
  parchment,
}

/// Human-readable labels for theme variant selectors.
String appThemeVariantLabel(AppThemeVariant variant) => switch (variant) {
  AppThemeVariant.clinic => 'Astro Vista',
  AppThemeVariant.parchment => 'Claude+',
};
