import 'package:flutter/material.dart';

import 'package:ai_clinic/core/auth/permission_service.dart';

/// Brief permission-denied feedback for blocked routes and actions (FR-009a).
abstract final class PermissionDeniedHandler {
  static const defaultMessage = 'You do not have permission to perform this action.';

  /// Shows a short snackbar; safe to call when [context] has a [ScaffoldMessenger].
  static void show(BuildContext context, {String? message}) {
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        return;
      }

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message ?? defaultMessage),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      // No scaffold ancestor (e.g. orphan context in tests) — fail silently.
    }
  }

  /// Runs [action] after [requirePermission]; shows denied snackbar on failure.
  static void runIfPermitted(
    BuildContext context, {
    required PermissionService permissions,
    required String permissionKey,
    required VoidCallback action,
    String? deniedMessage,
  }) {
    try {
      permissions.requirePermission(permissionKey);
      action();
    } on PermissionDeniedException {
      show(context, message: deniedMessage);
    }
  }
}
