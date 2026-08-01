import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigations_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachments_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_stagger.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_text_section.dart';

/// Treatment phase section (web `TreatmentSection`).
class TreatmentSection extends ConsumerStatefulWidget {
  const TreatmentSection({required this.visitId, super.key});

  final String visitId;

  @override
  ConsumerState<TreatmentSection> createState() => _TreatmentSectionState();
}

class _TreatmentSectionState extends ConsumerState<TreatmentSection> with SingleTickerProviderStateMixin {
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
    final auth = ref.watch(authSessionProvider);
    final staff = auth.context?.staffProfile;
    final canUploadAttachments = canEdit && staff != null;
    final attachments = state.effectiveVisit.attachments;

    return VisitStagger(
      vsync: this,
      stepMs: 40,
      children: [
        VisitStaggeredItem(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Treatment', style: AppTypography.title(context).copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.space1),
              Text(
                'Plan investigations, prescribe treatments, and attach supporting documents.',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        VisitStaggeredItem(
          child: VisitTextSection(
            visitId: widget.visitId,
            section: ClinicalNoteSection.plan,
            id: 'treatment-notes',
            label: 'Treatment notes',
            hint: 'Clinical reasoning, patient education, and follow-up instructions.',
            placeholder: 'Rest, hydration, return if symptoms worsen…',
            rows: 3,
            value: state.plan,
            richDelta: state.richTextDrafts[ClinicalNoteSection.plan],
            readOnly: !canEdit,
            onChanged: (plain, delta) => notifier.updatePlan(plain, richDelta: delta),
          ),
        ),
        VisitStaggeredItem(
          child: AppFormField(
            id: 'investigations',
            label: 'Investigations needed',
            helperText: 'Add each test via the dialog with any relevant clinical notes.',
            child: InvestigationsEditor(visitId: widget.visitId),
          ),
        ),
        VisitStaggeredItem(
          child: AppFormField(
            id: 'treatment-plan',
            label: 'Treatment plan',
            helperText: 'Add each prescription via the dialog with dosage, frequency, and duration.',
            child: TreatmentPlanEditor(visitId: widget.visitId),
          ),
        ),
        VisitStaggeredItem(
          child: AppFormField(
            id: 'documents',
            label: 'Attachments',
            helperText: 'Upload lab results, referrals, or other visit documents (PDF, JPG, PNG — max 10 MB).',
            child: VisitAttachmentsEditor(
              attachments: attachments,
              canEdit: canUploadAttachments,
              uploadedBy: staff?.staffMemberId ?? '',
              uploadedByName: staff?.fullName,
              onStage: ({required pick, required label, required uploadedBy, uploadedByName}) => notifier
                  .stageAttachment(pick: pick, label: label, uploadedBy: uploadedBy, uploadedByName: uploadedByName),
              onDelete: notifier.stageDeleteAttachment,
            ),
          ),
        ),
      ],
    );
  }
}
