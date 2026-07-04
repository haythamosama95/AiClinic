import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

/// Advisory dialog when create/update finds likely duplicate patients (V1-3).
abstract final class DuplicateCandidatesDialog {
  DuplicateCandidatesDialog._();

  /// Returns `true` when the user chooses to continue despite duplicates.
  static Future<bool?> show(
    BuildContext context, {
    required List<DuplicateCandidate> candidates,
  }) {
    return showAppDialog<bool>(
      context,
      size: AppDialogSize.md,
      barrierDismissible: false,
      semanticLabel: 'Similar patients found',
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Similar patients found',
          onClose: () => close(false),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'These records may be the same person. Review before registering, '
                'or continue if this is a new patient.',
                style: dialogContext.typography.body.copyWith(
                  color: dialogContext.colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: dialogContext.colors.borderSubtle,
                  ),
                  itemBuilder: (context, index) {
                    return _CandidateTile(candidate: candidates[index]);
                  },
                ),
              ),
            ],
          ),
          footer: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: 'Go back',
                variant: AppButtonVariant.secondary,
                onPressed: () => close(false),
              ),
              AppButton(
                label: 'Continue anyway',
                onPressed: () => close(true),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate});

  final DuplicateCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;
    final dob = candidate.dateOfBirth;
    final dobLabel = dob == null ? null : PatientPresentationFormatting.date.format(dob);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            candidate.fullName,
            style: typography.bodyStrong.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            [
              if (candidate.phone != null && candidate.phone!.isNotEmpty) candidate.phone,
              ?dobLabel,
              candidate.branchName,
            ].whereType<String>().join(' · '),
            style: typography.bodySm.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
