/// Named design-system variants. Each variant owns its own token files.
enum AppThemeVariant {
  /// Astro Vista palette (orange primary, blue secondary).
  clinic,

  /// Claude+ palette (terracotta primary, cream surfaces).
  parchment,

  /// Med Spectra palette (purple primary, soft UI medical dashboard).
  medSpectra,

  /// eCarely palette (teal primary, mint-grey clinical dashboard).
  eCarely,
}

/// Human-readable labels for theme variant selectors.
String appThemeVariantLabel(AppThemeVariant variant) => switch (variant) {
  AppThemeVariant.clinic => 'Astro Vista',
  AppThemeVariant.parchment => 'Claude+',
  AppThemeVariant.medSpectra => 'Med Spectra',
  AppThemeVariant.eCarely => 'eCarely',
};

/// Variants that use soft UI card shadows instead of bordered cards.
bool appThemeVariantUsesSoftUi(AppThemeVariant variant) => switch (variant) {
  AppThemeVariant.medSpectra || AppThemeVariant.eCarely => true,
  _ => false,
};
