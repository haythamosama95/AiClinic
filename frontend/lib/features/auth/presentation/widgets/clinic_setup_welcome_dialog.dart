import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Welcome dialog shown once after the first successful sign-in while clinic setup is still required.
abstract final class ClinicSetupWelcomeDialog {
  const ClinicSetupWelcomeDialog._();

  static const appName = 'AiClinic';

  static Future<void> show(BuildContext context) {
    return AppDialog.show<void>(
      context,
      title: 'Welcome to $appName',
      size: AppDialogSize.md,
      barrierDismissible: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'You are signed in as the clinic administrator. Before your team can use the workspace, '
            'we will walk you through a short setup for your organization, branches, staff, and services.',
            style: AppTypography.body(context).copyWith(color: context.appColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space4),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColorPrimitives.teal50.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColorPrimitives.teal300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_fix_high, size: 18, color: AppColorPrimitives.teal700),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Text(
                      'Next up: clinic setup. It only takes a few minutes, and you can adjust everything later in Settings.',
                      style: AppTypography.bodySm(context).copyWith(color: context.appColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      footer: Builder(
        builder: (dialogContext) => AppButton(
          variant: AppButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Start clinic setup'),
        ),
      ),
    );
  }
}
