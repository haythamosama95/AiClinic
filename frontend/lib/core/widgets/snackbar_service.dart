import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../errors/failures.dart';

/// Consistent transient feedback aligned with the shared snack bar theme.
abstract final class SnackbarService {
  static void showMessage(BuildContext context, String message, {Duration duration = const Duration(seconds: 4)}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: duration));
  }

  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.successContainer(Theme.of(context).brightness),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: AppColors.onSuccessContainer(Theme.of(context).brightness),
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
  }

  static void showFailure(BuildContext context, AppFailure failure) {
    final semanticsLabel = '${failure.title}: ${failure.message}';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Semantics(label: semanticsLabel, child: Text(failure.title)),
          behavior: SnackBarBehavior.floating,
          action: failure.recoverable
              ? SnackBarAction(
                  label: 'Dismiss',
                  textColor: Theme.of(context).colorScheme.onInverseSurface,
                  onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                )
              : null,
        ),
      );
  }
}
