import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';

/// Celebration dialog shown after first-time clinic setup finishes successfully.
abstract final class ClinicSetupCompleteDialog {
  const ClinicSetupCompleteDialog._();

  static Future<void> show(BuildContext context, {required SetupDraft draft}) {
    final orgName = draft.organization.name.trim();
    final branchCount = draft.branches.length;
    final staffCount = draft.staff.length;
    final serviceCount = draft.services.length;

    return AppDialog.show<void>(
      context,
      title: 'Your clinic is ready',
      size: AppDialogSize.md,
      barrierDismissible: false,
      showCloseButton: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColorPrimitives.teal50, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle_outline, size: 32, color: AppColorPrimitives.teal600),
          ),
          const SizedBox(height: AppSpacing.space6),
          Text(
            orgName.isEmpty ? 'Everything is configured' : '$orgName is good to go',
            textAlign: TextAlign.center,
            style: AppTypography.h3(context).copyWith(color: context.appColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'You have $branchCount ${_pluralize(branchCount, 'branch', 'branches')}, '
            '$staffCount ${_pluralize(staffCount, 'team member', 'team members')}, and '
            '$serviceCount ${_pluralize(serviceCount, 'service', 'services')} ready to use.',
            textAlign: TextAlign.center,
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
              child: Text(
                'You can refine any of these details later in Settings. For now, dive in and start managing your clinic.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm(context).copyWith(color: context.appColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
      footer: Builder(
        builder: (dialogContext) => AppButton(
          variant: AppButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Start exploring'),
        ),
      ),
    );
  }

  static String _pluralize(int count, String singular, String plural) => count == 1 ? singular : plural;
}
