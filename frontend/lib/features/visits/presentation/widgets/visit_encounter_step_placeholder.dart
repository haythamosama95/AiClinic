import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';

/// Placeholder body for a single encounter documentation step.
class VisitEncounterStepPlaceholder extends StatelessWidget {
  const VisitEncounterStepPlaceholder({required this.phase, super.key});

  final EncounterPhase phase;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final copy = _copyFor(phase);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(copy.icon, size: 32, color: colors.actionPrimary),
                const SizedBox(height: AppSpacing.space4),
                Text(
                  copy.title,
                  style: AppTypography.h3(context).copyWith(color: colors.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  copy.description,
                  style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static _StepCopy _copyFor(EncounterPhase phase) {
    return switch (phase) {
      EncounterPhase.subjective => const _StepCopy(
        icon: Icons.assignment_outlined,
        title: 'Intake',
        description: 'Record the patient complaint, history, and safety context for this visit.',
      ),
      EncounterPhase.objective => const _StepCopy(
        icon: Icons.biotech_outlined,
        title: 'Findings & diagnosis',
        description: 'Document examination findings, vitals, investigations, and diagnosis.',
      ),
      EncounterPhase.plan => const _StepCopy(
        icon: Icons.medical_services_outlined,
        title: 'Treatment',
        description: 'Plan treatment, prescriptions, follow-up, and visit attachments.',
      ),
      EncounterPhase.context || EncounterPhase.review => const _StepCopy(
        icon: Icons.summarize_outlined,
        title: 'Summary',
        description: 'Review the completed encounter before finishing the visit.',
      ),
    };
  }
}

class _StepCopy {
  const _StepCopy({required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;
}
