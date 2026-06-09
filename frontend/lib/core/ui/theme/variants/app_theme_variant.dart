/// Named design-system variants. Each variant owns its own token files.
enum AppThemeVariant {
  /// Original AiClinic palette (orange primary, blue secondary).
  clinic,

  /// Warm parchment palette (terracotta primary, cream surfaces).
  parchment,
}

/// Human-readable labels for theme variant chips.
String appThemeVariantLabel(AppThemeVariant variant) => switch (variant) {
  AppThemeVariant.clinic => 'Clinic',
  AppThemeVariant.parchment => 'Parchment',
};
