import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/medical_background_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_stagger.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_text_section.dart';

/// Patient intake section: complaint, history, and medical background placeholder.
class IntakeSection extends ConsumerStatefulWidget {
  const IntakeSection({required this.visitId, super.key});

  final String visitId;

  @override
  ConsumerState<IntakeSection> createState() => _IntakeSectionState();
}

class _IntakeSectionState extends ConsumerState<IntakeSection> with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(visitDocumentationProvider(widget.visitId));

    return docAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (state) {
        final colors = context.appColors;
        final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
        final canEdit = state.canEditWorkspace(ref.read(permissionServiceProvider).canEditVisitSoap());

        return VisitStagger(
          vsync: this,
          stepMs: 40,
          children: [
            VisitStaggeredItem(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Patient intake', style: AppTypography.title(context)),
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      'Record the presenting complaint and relevant medical background.',
                      style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            VisitStaggeredItem(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space6),
                child: VisitTextSection(
                  visitId: widget.visitId,
                  section: ClinicalNoteSection.complaint,
                  id: 'complaint',
                  label: 'Chief complaint',
                  required: true,
                  hint: 'The primary reason for today\'s visit, in the patient\'s own words.',
                  placeholder: 'e.g. Persistent cough for two weeks…',
                  value: state.complaint,
                  richDelta: state.richTextDrafts[ClinicalNoteSection.complaint],
                  rows: 3,
                  readOnly: !canEdit,
                  onChanged: (plain, delta) => notifier.updateComplaint(plain, richDelta: delta),
                ),
              ),
            ),
            VisitStaggeredItem(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space6),
                child: VisitTextSection(
                  visitId: widget.visitId,
                  section: ClinicalNoteSection.history,
                  id: 'history',
                  label: 'History of present illness',
                  hint: 'Onset, duration, severity, aggravating and relieving factors.',
                  placeholder: 'Describe the timeline and progression…',
                  value: state.history,
                  richDelta: state.richTextDrafts[ClinicalNoteSection.history],
                  rows: 4,
                  readOnly: !canEdit,
                  onChanged: (plain, delta) => notifier.updateHistory(plain, richDelta: delta),
                ),
              ),
            ),
            VisitStaggeredItem(child: MedicalBackgroundEditor(visitId: widget.visitId)),
          ],
        );
      },
    );
  }
}
