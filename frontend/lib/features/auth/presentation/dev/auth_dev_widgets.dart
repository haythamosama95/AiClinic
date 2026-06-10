import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Local bootstrap administrator credentials (see backend seed migrations).
abstract final class AuthDevBootstrapCredentials {
  static const username = 'admin';
  static const password = 'admin';
}

/// Debug-only auth presentation widgets (permission demo, quick admin sign-in, etc.).
///
/// Widgets in this library must only be rendered behind [kDebugMode] or via
/// conditional imports so they are excluded from release builds.
abstract final class AuthDevWidgets {
  const AuthDevWidgets._();

  /// Dev-only shortcuts shown beneath the login modal. Removed before production.
  static Widget panel({Key? key, required VoidCallback onLoginAsAdmin, bool isSubmitting = false}) {
    if (!kDebugMode) return const SizedBox.shrink();

    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: SpacingTokens.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DEV ONLY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: Colors.orange.shade800,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          AppButton(
            label: 'Login as admin',
            variant: AppButtonVariant.outline,
            expand: false,
            isLoading: isSubmitting,
            onPressed: isSubmitting ? null : onLoginAsAdmin,
          ),
        ],
      ),
    );
  }
}
