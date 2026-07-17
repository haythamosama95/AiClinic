import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_step_rail.dart';

/// Patient identity and encounter step rail for visit documentation.
class VisitEncounterHeader extends StatelessWidget {
  const VisitEncounterHeader({
    required this.patientName,
    required this.currentPhase,
    this.patientAgeLabel,
    this.onPhaseSelected,
    super.key,
  });

  final String patientName;
  final String? patientAgeLabel;
  final EncounterPhase currentPhase;
  final ValueChanged<EncounterPhase>? onPhaseSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 720;

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PatientIdentity(patientName: patientName, patientAgeLabel: patientAgeLabel),
                  const SizedBox(height: AppSpacing.space4),
                  const AppDivider(),
                  const SizedBox(height: AppSpacing.space4),
                  Center(
                    child: VisitEncounterStepRail(currentPhase: currentPhase, onPhaseSelected: onPhaseSelected),
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _PatientIdentity(patientName: patientName, patientAgeLabel: patientAgeLabel),
                const SizedBox(width: AppSpacing.space5),
                const SizedBox(height: 48, child: AppDivider(orientation: DividerOrientation.vertical)),
                const SizedBox(width: AppSpacing.space5),
                Expanded(
                  child: Center(
                    child: VisitEncounterStepRail(currentPhase: currentPhase, onPhaseSelected: onPhaseSelected),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PatientIdentity extends StatelessWidget {
  const _PatientIdentity({required this.patientName, this.patientAgeLabel});

  final String patientName;
  final String? patientAgeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppAvatar(name: patientName, size: AvatarSize.lg),
        const SizedBox(width: AppSpacing.space3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(patientName, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
            if (patientAgeLabel != null) ...[
              const SizedBox(height: 2),
              Text(patientAgeLabel!, style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary)),
            ],
          ],
        ),
      ],
    );
  }
}
