import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_step_rail.dart';

/// Patient and visit context banner with embedded step rail (web `VisitPatientBanner`).
class VisitPatientBanner extends ConsumerWidget {
  const VisitPatientBanner({required this.visitId, this.onPhaseSelect, super.key});

  final String visitId;
  final ValueChanged<EncounterPhase>? onPhaseSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(visitDetailViewProvider(visitId));

    return Semantics(
      container: true,
      label: 'Visit context',
      child: detailAsync.when(
        loading: () => AppCard(
          variant: CardVariant.raised,
          padding: CardPadding.sm,
          child: const AppSkeletonizerZone(
            child: Row(
              children: [
                AppSkeleton(variant: SkeletonVariant.circular, width: 32, height: 32),
                SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeleton(variant: SkeletonVariant.rectangular, width: 160, height: 18),
                      SizedBox(height: AppSpacing.space1),
                      AppSkeleton(variant: SkeletonVariant.rectangular, width: 80, height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        error: (_, _) => AppCard(
          variant: CardVariant.raised,
          padding: CardPadding.sm,
          child: _VisitContextBody(
            displayName: _patientDisplayName(visitId),
            avatarName: visitId,
            metaLine: 'Patient details unavailable',
            visitId: visitId,
            onPhaseSelect: onPhaseSelect ?? (phase) => _defaultPhaseSelect(ref, visitId, phase),
          ),
        ),
        data: (view) {
          final patientAsync = ref.watch(patientDetailProvider(view.visit.patientId));
          final onSelect = onPhaseSelect ?? (phase) => _defaultPhaseSelect(ref, visitId, phase);

          return patientAsync.when(
            loading: () => AppCard(
              variant: CardVariant.raised,
              padding: CardPadding.sm,
              child: _VisitContextBody(
                displayName: _patientDisplayName(view.visit.patientId),
                avatarName: view.visit.patientId,
                metaLine: 'Loading patient…',
                visitId: visitId,
                onPhaseSelect: onSelect,
              ),
            ),
            error: (_, _) => AppCard(
              variant: CardVariant.raised,
              padding: CardPadding.sm,
              child: _VisitContextBody(
                displayName: _patientDisplayName(view.visit.patientId),
                avatarName: view.visit.patientId,
                metaLine: 'Patient details unavailable',
                visitId: visitId,
                onPhaseSelect: onSelect,
              ),
            ),
            data: (patient) => AppCard(
              variant: CardVariant.raised,
              padding: CardPadding.sm,
              child: _VisitContextBody(
                displayName: patient.fullName,
                avatarName: patient.fullName,
                metaLine: _patientAgeLine(patient.dateOfBirth),
                visitId: visitId,
                onPhaseSelect: onSelect,
              ),
            ),
          );
        },
      ),
    );
  }

  void _defaultPhaseSelect(WidgetRef ref, String visitId, EncounterPhase phase) {
    ref.read(encounterActivePhaseProvider(visitId).notifier).setPhase(phase);
  }
}

class _VisitContextBody extends StatelessWidget {
  const _VisitContextBody({
    required this.displayName,
    required this.avatarName,
    required this.metaLine,
    required this.visitId,
    required this.onPhaseSelect,
  });

  final String displayName;
  final String avatarName;
  final String metaLine;
  final String visitId;
  final ValueChanged<EncounterPhase> onPhaseSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isWide = MediaQuery.sizeOf(context).width >= 640;

    final identityText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
        ),
        if (metaLine.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            metaLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(
              context,
            ).copyWith(color: colors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ],
    );

    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: isWide ? MainAxisSize.min : MainAxisSize.max,
      children: [
        AppAvatar(name: avatarName, size: AvatarSize.md),
        const SizedBox(width: AppSpacing.space3),
        if (isWide) identityText else Flexible(fit: FlexFit.loose, child: identityText),
      ],
    );

    final stepRail = VisitStepRail(visitId: visitId, onPhaseSelect: onPhaseSelect);

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          identity,
          const SizedBox(height: AppSpacing.space3),
          stepRail,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        identity,
        const SizedBox(width: AppSpacing.space5),
        SizedBox(height: 28, child: VerticalDivider(width: 1, thickness: 1, color: colors.borderSubtle)),
        const SizedBox(width: AppSpacing.space6),
        Expanded(child: stepRail),
      ],
    );
  }
}

String visitPatientDisplayName(String patientId) => _patientDisplayName(patientId);

String _patientDisplayName(String patientId) {
  final trimmed = patientId.trim();
  if (trimmed.isEmpty) {
    return 'Patient';
  }
  if (trimmed.length <= 8) {
    return 'Patient $trimmed';
  }
  return 'Patient ···${trimmed.substring(trimmed.length - 4)}';
}

String _patientAgeLine(DateTime? dateOfBirth) {
  final age = PatientPresentationFormatting.ageYears(dateOfBirth);
  if (age == null) {
    return '';
  }
  return '$age years old';
}
