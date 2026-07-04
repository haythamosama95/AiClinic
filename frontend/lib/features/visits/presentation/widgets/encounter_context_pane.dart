import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_patient_safety_panel.dart';

/// Patient context pane — profile card, vitals, and safety summary.
class EncounterContextPane extends ConsumerWidget {
  const EncounterContextPane({
    required this.visitId,
    required this.state,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientId = state.visit.patientId;
    final patientAsync = ref.watch(patientDetailProvider(patientId));
    final safetyAsync = ref.watch(patientSafetyProvider(patientId));
    final vitals = state.visit.vitalSigns;

    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          patientAsync.when(
            loading: () => const AppSkeleton(height: 96),
            error: (_, _) => AppCard(
              padding: AppCardPadding.sm,
              child: Text(
                'Patient ${PatientPresentationFormatting.displayId(patientId)}',
                style: context.typography.bodyStrong,
              ),
            ),
            data: (patient) {
              final allergyTags = safetyAsync.value?.allergies
                      .map((a) => a.substance)
                      .take(3)
                      .toList() ??
                  const <String>[];

              return PatientCard(
                name: patient.fullName,
                mrn: PatientPresentationFormatting.displayId(patient.id),
                phone: PatientPresentationFormatting.orDash(patient.phone),
                tags: allergyTags,
              );
            },
          ),
          const SizedBox(height: AppSpacing.s4),
          AppSectionHeader(title: 'Vitals'),
          const SizedBox(height: AppSpacing.s2),
          if (vitals.isEmpty)
            Text(
              'No vitals recorded yet.',
              style: context.typography.bodySm.copyWith(color: context.colors.textTertiary),
            )
          else
            _VitalsList(vitalSigns: vitals),
          const SizedBox(height: AppSpacing.s4),
          AppSectionHeader(title: 'Patient safety'),
          const SizedBox(height: AppSpacing.s2),
          EncounterPatientSafetyPanel(
            visitId: visitId,
            patientId: patientId,
            canEdit: false,
          ),
        ],
      ),
    );
  }
}

class _VitalsList extends StatelessWidget {
  const _VitalsList({required this.vitalSigns});

  final List<VisitVitalSign> vitalSigns;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      children: [
        for (final sign in vitalSigns)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    sign.name,
                    style: typography.bodySm.copyWith(color: colors.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Flexible(
                  child: Text(
                    '${sign.value}${sign.unit != null && sign.unit!.isNotEmpty ? ' ${sign.unit}' : ''}',
                    style: typography.tabular(typography.bodySm).copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
