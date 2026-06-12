import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/widgets/buttons/app_button.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_field_size.dart';

/// Application dialog helpers wrapping [FDialog] and [showFDialog].
abstract final class AppDialog {
  static const _actionSize = AppFieldSize.sm;

  /// Shows a dialog with custom title, body, and actions.
  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    required Widget body,
    List<Widget>? actions,
    Axis direction = Axis.horizontal,
    bool barrierDismissible = true,
  }) {
    final fTheme = context.theme;
    final materialTheme = Theme.of(context);

    return showFDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext, style, animation) {
        return FTheme(
          data: fTheme,
          child: FDialog(
            style: style,
            animation: animation,
            direction: direction,
            title: title == null ? null : Text(title, style: materialTheme.textTheme.titleLarge),
            body: body,
            actions: actions ?? const [],
          ),
        );
      },
    );
  }

  /// Shows a horizontal confirmation dialog with confirm and cancel actions.
  ///
  /// When [destructive] is true, the confirm action uses destructive styling and the
  /// cancel action uses primary styling so the safe choice is visually prominent.
  static Future<void> showConfirmation({
    required BuildContext context,
    required String title,
    required String message,
    required VoidCallback onConfirm,
    String? confirmLabel,
    String? cancelLabel,
    bool destructive = false,
  }) {
    final fTheme = context.theme;
    final materialTheme = Theme.of(context);
    final confirmVariant = destructive ? AppButtonVariant.destructive : AppButtonVariant.primary;
    final cancelVariant = destructive ? AppButtonVariant.primary : AppButtonVariant.secondary;

    return showFDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext, style, animation) {
        return FTheme(
          data: fTheme,
          child: FDialog(
            style: style,
            animation: animation,
            direction: Axis.horizontal,
            title: Text(title, style: materialTheme.textTheme.titleLarge),
            body: Text(message, style: materialTheme.textTheme.bodyMedium),
            actions: [
              _action(
                label: confirmLabel ?? 'Confirm',
                variant: confirmVariant,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  onConfirm();
                },
              ),
              _action(
                label: cancelLabel ?? 'Cancel',
                variant: cancelVariant,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _action({required String label, required AppButtonVariant variant, required VoidCallback onPressed}) {
    return AppButton(label: label, variant: variant, size: _actionSize, onPressed: onPressed);
  }
}
