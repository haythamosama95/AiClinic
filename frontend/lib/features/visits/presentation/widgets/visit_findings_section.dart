import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_vital_signs_editor.dart';

/// Findings step — physical examination, vital signs, and diagnosis.
class VisitFindingsSection extends ConsumerWidget {
  const VisitFindingsSection({required this.visitId, required this.canEdit, super.key});

  final String visitId;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(visitDocumentationProvider(visitId));
    final docState = docAsync.value;
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    final vitalSigns = docState?.effectiveVisit.vitalSigns ?? const [];
    final catalog = docState?.predefinedVitalSigns ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Findings & diagnosis', style: AppTypography.h2(context)),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Document physical examination, vital signs, and clinical assessment.',
          style: AppTypography.bodySm(context).copyWith(color: context.appColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space6),
        ClinicalNoteField(
          visitId: visitId,
          section: ClinicalNoteSection.examination,
          fieldId: 'physical-examination',
          editorId: 'physical-examination-input',
          label: 'Physical examination',
          hint: 'Objective findings from the clinical examination.',
          placeholder: 'General appearance, systems examined, notable findings…',
          canEdit: canEdit,
        ),
        const SizedBox(height: AppSpacing.space6),
        AppFormField(
          id: 'vital-signs',
          label: 'Vital signs',
          helperText: 'Add each measurement via the dialog; recorded values appear as cards below.',
          child: VisitVitalSignsEditor(
            entries: vitalSigns,
            catalog: catalog,
            canEdit: canEdit,
            onCreate: ({required name, required value, unit, predefinedVitalSignId}) => notifier.stageCreateVitalSign(
              name: name,
              value: value,
              unit: unit,
              predefinedVitalSignId: predefinedVitalSignId,
            ),
            onUpdate: (id, {required name, required value, unit, predefinedVitalSignId}) =>
                notifier.stageUpdateVitalSign(
                  vitalSignId: id,
                  name: name,
                  value: value,
                  unit: unit,
                  predefinedVitalSignId: predefinedVitalSignId,
                ),
            onArchive: notifier.stageArchiveVitalSign,
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        ClinicalNoteField(
          visitId: visitId,
          section: ClinicalNoteSection.diagnosis,
          fieldId: 'diagnosis',
          editorId: 'diagnosis-input',
          label: 'Diagnosis',
          requiredMark: true,
          hint: 'Primary and secondary diagnoses for this encounter.',
          placeholder: 'e.g. Acute upper respiratory infection (J06.9)…',
          canEdit: canEdit,
        ),
      ],
    );
  }
}
