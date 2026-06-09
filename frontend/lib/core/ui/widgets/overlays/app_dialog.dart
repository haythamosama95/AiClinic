import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/widgets/buttons/app_button.dart';

/// Application dialog helpers wrapping [FDialog] and [showFDialog].
abstract final class AppDialog {
  /// Shows a dialog with custom title, body, and actions.
  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    required Widget body,
    List<Widget>? actions,
    Axis direction = Axis.horizontal,
    bool barrierDismissible = true,
  }) {
    return showFDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext, style, animation) {
        final theme = Theme.of(dialogContext);

        return FTheme(
          data: dialogContext.theme,
          child: FDialog(
            style: style,
            animation: animation,
            direction: direction,
            title: title == null ? null : Text(title, style: theme.textTheme.titleLarge),
            body: body,
            actions: actions ?? const [],
          ),
        );
      },
    );
  }

  /// Shows a horizontal confirmation dialog with confirm and cancel actions.
  static Future<void> showConfirmation({
    required BuildContext context,
    required String title,
    required String message,
    required VoidCallback onConfirm,
    String? confirmLabel,
    String? cancelLabel,
    AppButtonVariant confirmVariant = AppButtonVariant.primary,
  }) {
    return showFDialog<void>(
      context: context,
      builder: (dialogContext, style, animation) {
        final theme = Theme.of(dialogContext);

        return FTheme(
          data: dialogContext.theme,
          child: FDialog(
            style: style,
            animation: animation,
            direction: Axis.horizontal,
            title: Text(title, style: theme.textTheme.titleLarge),
            body: Text(message, style: theme.textTheme.bodyMedium),
            actions: [
              AppButton(
                label: confirmLabel ?? 'Confirm',
                variant: confirmVariant,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  onConfirm();
                },
              ),
              AppButton(
                label: cancelLabel ?? 'Cancel',
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
}
