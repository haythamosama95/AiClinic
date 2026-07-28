import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/components/app_list.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

/// Duplicate-patient confirmation dialog (web `DuplicatePatientDialog`).
class DuplicatePatientDialog extends StatelessWidget {
  const DuplicatePatientDialog({
    required this.open,
    required this.onOpenChange,
    required this.candidates,
    required this.onRegisterAnyway,
    required this.onOpenPatient,
    this.loading = false,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final List<DuplicateCandidate> candidates;
  final VoidCallback onRegisterAnyway;
  final ValueChanged<String> onOpenPatient;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final countLabel = candidates.length == 1
        ? '1 existing patient matches the details you entered.'
        : '${candidates.length} existing patients match the details you entered.';

    return AppDialog(
      open: open,
      onOpenChange: onOpenChange,
      title: 'Possible duplicate found',
      description:
          'A patient with similar details already exists. Review the matches below before creating a new record.',
      size: AppDialogSize.md,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            variant: AppButtonVariant.secondary,
            disabled: loading,
            onPressed: loading ? null : () => onOpenChange(false),
            child: const Text('Go back'),
          ),
          const SizedBox(width: AppSpacing.space2),
          AppButton(
            variant: AppButtonVariant.primary,
            loading: loading,
            onPressed: loading ? null : onRegisterAnyway,
            child: const Text('Register anyway'),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            countLabel,
            style: AppTypography.bodySm(
              context,
            ).copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space4),
          AppList(
            children: [
              for (final candidate in candidates)
                AppListItem(
                  key: ValueKey(candidate.id),
                  leading: AppAvatar(
                    name: candidate.fullName,
                    size: AvatarSize.sm,
                  ),
                  primary: Text(candidate.fullName),
                  secondary: Text(_secondaryLabel(candidate)),
                  trailing: AppButton(
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    leadingIcon: const Icon(Icons.open_in_new, size: 14),
                    onPressed: () => onOpenPatient(candidate.id),
                    child: const Text('Open'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _secondaryLabel(DuplicateCandidate candidate) {
    final parts = <String>[candidate.branchName];
    if (candidate.phone != null && candidate.phone!.isNotEmpty) {
      parts.add(candidate.phone!);
    }
    if (candidate.dateOfBirth != null) {
      parts.add(
        'DOB ${PatientPresentationFormatting.dateOfBirthLabel(candidate.dateOfBirth)}',
      );
    }
    return parts.join(' · ');
  }
}
