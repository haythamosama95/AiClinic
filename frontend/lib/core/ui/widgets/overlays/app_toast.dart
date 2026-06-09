import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Application toast helpers wrapping [showFToast].
abstract final class AppToast {
  static void success(
    BuildContext context, {
    required String message,
    String? description,
    Duration duration = const Duration(seconds: 5),
  }) {
    final theme = Theme.of(context);

    showFToast(
      context: context,
      variant: FToastVariant.primary,
      icon: Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
      title: Text(message, style: theme.textTheme.bodyMedium),
      description: description == null ? null : Text(description, style: theme.textTheme.bodySmall),
      duration: duration,
    );
  }

  static void error(
    BuildContext context, {
    required String message,
    String? description,
    Duration duration = const Duration(seconds: 5),
  }) {
    final theme = Theme.of(context);

    showFToast(
      context: context,
      variant: FToastVariant.destructive,
      icon: Icon(Icons.error_outline, color: theme.colorScheme.error),
      title: Text(message, style: theme.textTheme.bodyMedium),
      description: description == null ? null : Text(description, style: theme.textTheme.bodySmall),
      duration: duration,
    );
  }
}
