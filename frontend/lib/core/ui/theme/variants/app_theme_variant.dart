/// Named design-system variants. Each variant owns its own token files.
enum AppThemeVariant {
  /// Astro Vista palette (orange primary, blue secondary).
  clinic,

  /// Claude+ palette (terracotta primary, cream surfaces).
  parchment,

  /// Med Spectra palette (purple primary, soft UI medical dashboard).
  medSpectra,
}

/// Human-readable labels for theme variant selectors.
String appThemeVariantLabel(AppThemeVariant variant) => switch (variant) {
  AppThemeVariant.clinic => 'Astro Vista',
  AppThemeVariant.parchment => 'Claude+',
  AppThemeVariant.medSpectra => 'Med Spectra',
};
