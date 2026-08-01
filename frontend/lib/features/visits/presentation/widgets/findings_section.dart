import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_signs_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_stagger.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_text_section.dart';

/// Findings & diagnosis phase section (web `FindingsSection`).
class FindingsSection extends ConsumerStatefulWidget {
  const FindingsSection({required this.visitId, super.key});

  final String visitId;

  @override
  ConsumerState<FindingsSection> createState() => _FindingsSectionState();
}

class _FindingsSectionState extends ConsumerState<FindingsSection> with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(visitDocumentationProvider(widget.visitId));
    final state = doc.value;
    if (state == null) {
      return const SizedBox.shrink();
    }

    final colors = context.appColors;
    final canEdit = state.canEditWorkspace(ref.read(permissionServiceProvider).canEditVisitSoap());
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);

    return VisitStagger(
      vsync: this,
      stepMs: 40,
      children: [
        VisitStaggeredItem(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Findings & diagnosis', style: AppTypography.title(context).copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.space1),
              Text(
                'Document physical examination, vital signs, and clinical assessment.',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        VisitStaggeredItem(
          child: VisitTextSection(
            visitId: widget.visitId,
            section: ClinicalNoteSection.examination,
            id: 'examination',
            label: 'Physical examination',
            hint: 'Objective findings from the clinical examination.',
            placeholder: 'General appearance, systems examined, notable findings…',
            rows: 4,
            value: state.examination,
            richDelta: state.richTextDrafts[ClinicalNoteSection.examination],
            readOnly: !canEdit,
            onChanged: (plain, delta) => notifier.updateExamination(plain, richDelta: delta),
          ),
        ),
        VisitStaggeredItem(
          child: AppFormField(
            id: 'vital-signs',
            label: 'Vital signs',
            helperText: 'Add each measurement via the dialog; recorded values appear as cards below.',
            child: VitalSignsEditor(visitId: widget.visitId),
          ),
        ),
        VisitStaggeredItem(
          child: VisitTextSection(
            visitId: widget.visitId,
            section: ClinicalNoteSection.diagnosis,
            id: 'diagnosis',
            label: 'Diagnosis',
            required: true,
            hint: 'Primary and secondary diagnoses for this encounter.',
            placeholder: 'e.g. Acute upper respiratory infection (J06.9)…',
            rows: 3,
            value: state.diagnosis,
            richDelta: state.richTextDrafts[ClinicalNoteSection.diagnosis],
            readOnly: !canEdit,
            onChanged: (plain, delta) => notifier.updateDiagnosis(plain, richDelta: delta),
          ),
        ),
      ],
    );
  }
}
