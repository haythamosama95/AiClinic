import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Spinner size tokens for inline and button-scoped loading.
enum AppSpinnerSize { sm, md, lg }

/// House loading spinner styled with design-system colors.
class AppSpinner extends StatelessWidget {
  const AppSpinner({
    super.key,
    this.size = AppSpinnerSize.md,
    this.semanticLabel,
  });

  final AppSpinnerSize size;
  final String? semanticLabel;

  static double dimensionFor(AppSpinnerSize size) => switch (size) {
    AppSpinnerSize.sm => 16,
    AppSpinnerSize.md => 20,
    AppSpinnerSize.lg => 24,
  };

  static double strokeWidthFor(AppSpinnerSize size) => switch (size) {
    AppSpinnerSize.sm => 2,
    AppSpinnerSize.md => 2.25,
    AppSpinnerSize.lg => 2.5,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dimension = dimensionFor(size);
    final stroke = strokeWidthFor(size);

    final indicator = SizedBox(
      width: dimension,
      height: dimension,
      child: CircularProgressIndicator(
        strokeWidth: stroke,
        color: colors.actionPrimary,
        backgroundColor: colors.borderSubtle,
      ),
    );

    if (semanticLabel == null) return indicator;

    return Semantics(label: semanticLabel, liveRegion: true, child: indicator);
  }
}
