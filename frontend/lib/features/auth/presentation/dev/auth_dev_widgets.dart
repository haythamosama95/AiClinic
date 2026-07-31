import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_reset_clinic.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Local bootstrap administrator credentials (see backend seed migrations).
abstract final class AuthDevBootstrapCredentials {
  static const username = 'admin';
  static const password = 'admin';
}

/// Debug-only auth presentation widgets (permission demo, quick admin sign-in, etc.).
abstract final class AuthDevWidgets {
  const AuthDevWidgets._();

  /// Dev-only shortcuts shown beneath the login modal. Removed before production.
  static Widget panel({
    Key? key,
    required VoidCallback onLoginAsAdmin,
    required VoidCallback onFillDummyClinic,
    required VoidCallback onResetClinic,
    bool isSubmitting = false,
  }) {
    if (!kDebugMode) return SizedBox.shrink(key: key);

    return Builder(
      key: key,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                children: [
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.md,
                    loading: isSubmitting,
                    onPressed: isSubmitting ? null : onLoginAsAdmin,
                    child: const Text('Dev login (admin)'),
                  ),
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.md,
                    loading: isSubmitting,
                    onPressed: isSubmitting ? null : onFillDummyClinic,
                    child: const Text(ShellDevFillDummyClinic.label),
                  ),
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.md,
                    loading: isSubmitting,
                    onPressed: isSubmitting ? null : onResetClinic,
                    child: const Text(ShellDevResetClinic.label),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space2),
              Text(
                'Debug builds only — uses local bootstrap credentials.',
                style: AppTypography.caption(context),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}
