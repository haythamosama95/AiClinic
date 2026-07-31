import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/patient_safety_editor.dart';

/// Medical background block with allergies, medications, and chronic conditions.
class MedicalBackgroundEditor extends ConsumerWidget {
  const MedicalBackgroundEditor({required this.visitId, super.key});

  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(visitDocumentationProvider(visitId));

    return docAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (state) {
        final colors = context.appColors;
        final patientId = state.visit.patientId;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceDefault,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Medical background', style: AppTypography.title(context)),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  'Chronic conditions, allergies, and current medications relevant to this visit.',
                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space5),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useColumns = constraints.maxWidth >= 900;
                    final editors = [
                      PatientSafetyEditor(
                        visitId: visitId,
                        patientId: patientId,
                        kind: PatientSafetyKind.condition,
                      ),
                      PatientSafetyEditor(
                        visitId: visitId,
                        patientId: patientId,
                        kind: PatientSafetyKind.allergy,
                      ),
                      PatientSafetyEditor(
                        visitId: visitId,
                        patientId: patientId,
                        kind: PatientSafetyKind.medication,
                      ),
                    ];

                    if (!useColumns) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0; index < editors.length; index++) ...[
                            editors[index],
                            if (index < editors.length - 1) const SizedBox(height: AppSpacing.space5),
                          ],
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0; index < editors.length; index++) ...[
                          Expanded(child: editors[index]),
                          if (index < editors.length - 1) const SizedBox(width: AppSpacing.space4),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
