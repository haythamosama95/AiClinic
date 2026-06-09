import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Layout options for [AppLabel].
enum AppLabelLayout { vertical, horizontalLeading, horizontalTrailing }

/// Application label wrapping [FLabel] with theme-driven typography.
class AppLabel extends StatelessWidget {
  const AppLabel({
    required this.child,
    this.label,
    this.description,
    this.error,
    this.layout = AppLabelLayout.vertical,
    this.expands = false,
    super.key,
  });

  final Widget child;
  final String? label;
  final String? description;
  final String? error;
  final AppLabelLayout layout;
  final bool expands;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FLabel(
      layout: _mapLayout(layout),
      expands: expands,
      label: label == null ? null : Text(label!, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      error: error == null
          ? null
          : Text(error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
      child: child,
    );
  }

  FLabelLayout _mapLayout(AppLabelLayout layout) => switch (layout) {
    AppLabelLayout.vertical => FLabelLayout.vertical,
    AppLabelLayout.horizontalLeading => FLabelLayout.horizontalLeading,
    AppLabelLayout.horizontalTrailing => FLabelLayout.horizontalTrailing,
  };
}
