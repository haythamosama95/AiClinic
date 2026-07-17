import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/rich_text_draft_utils.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachments_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_investigations_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_treatment_plan_editor.dart';

/// Treatment step — plan notes, investigations, prescriptions, and attachments.
class VisitTreatmentSection extends ConsumerStatefulWidget {
  const VisitTreatmentSection({required this.visitId, required this.canEdit, super.key});

  final String visitId;
  final bool canEdit;

  @override
  ConsumerState<VisitTreatmentSection> createState() => _VisitTreatmentSectionState();
}

class _VisitTreatmentSectionState extends ConsumerState<VisitTreatmentSection> {
  late final QuillController _planController;
  late final FocusNode _planFocusNode;
  late final VoidCallback _planFlush;
  VisitDocumentationNotifier? _documentationNotifier;
  var _flushRegistered = false;
  var _syncingFromState = false;

  @override
  void initState() {
    super.initState();
    _planController = QuillController.basic();
    _planFocusNode = FocusNode();
    _planFlush = () => _flushController(_planController);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncFromProvider();
      if (widget.canEdit) {
        _registerFlushCallbacks(ref.read(visitDocumentationProvider(widget.visitId).notifier));
      }
    });
  }

  @override
  void dispose() {
    _unregisterFlushCallbacks();
    _planFocusNode.dispose();
    _planController.dispose();
    super.dispose();
  }

  void _registerFlushCallbacks(VisitDocumentationNotifier notifier) {
    if (_flushRegistered) {
      return;
    }
    _documentationNotifier = notifier;
    notifier.registerClinicalNoteFlush(_planFlush);
    _flushRegistered = true;
  }

  void _unregisterFlushCallbacks() {
    if (!_flushRegistered) {
      return;
    }
    _documentationNotifier?.unregisterClinicalNoteFlush(_planFlush);
    _documentationNotifier = null;
    _flushRegistered = false;
  }

  void _syncFromProvider() {
    final state = ref.read(visitDocumentationProvider(widget.visitId)).value;
    if (state != null) {
      _syncControllers(state);
    }
  }

  void _scheduleSyncFromProvider() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncFromProvider();
      }
    });
  }

  void _flushController(QuillController controller) {
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final plainText = plainTextFromQuillDocument(controller.document);
    final richDelta = richDeltaFromQuillDocument(controller.document);
    notifier.updatePlan(plainText, richDelta: richDelta);
  }

  void _syncControllers(VisitDocumentationState state) {
    _syncQuillController(_planController, _planFocusNode, state.richTextDrafts[ClinicalNoteSection.plan], state.plan);
  }

  void _syncQuillController(
    QuillController controller,
    FocusNode focusNode,
    List<dynamic>? deltaJson,
    String plainText,
  ) {
    if (focusNode.hasFocus) {
      return;
    }

    final currentPlain = plainTextFromQuillDocument(controller.document);
    final currentDelta = richDeltaFromQuillDocument(controller.document);
    final targetDelta = richDeltaIsEffectivelyEmpty(deltaJson) ? null : deltaJson;

    if (currentPlain == plainText && _deltaEquals(currentDelta, targetDelta)) {
      return;
    }

    _syncingFromState = true;
    try {
      setQuillControllerFromDraft(controller, deltaJson, plainText);
    } finally {
      _syncingFromState = false;
    }
  }

  bool _deltaEquals(List<dynamic>? a, List<dynamic>? b) {
    if (a == null && b == null) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    return a.toString() == b.toString();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(visitDocumentationProvider(widget.visitId), (previous, next) {
      if (previous?.value != next.value) {
        _scheduleSyncFromProvider();
      }
    });

    final docAsync = ref.watch(visitDocumentationProvider(widget.visitId));
    final docState = docAsync.value;
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final canEdit = widget.canEdit;
    final effectiveVisit = docState?.effectiveVisit;
    final investigations = effectiveVisit?.investigations ?? const [];
    final treatmentPlans = effectiveVisit?.treatmentPlans ?? const [];
    final attachments = effectiveVisit?.attachments ?? const [];
    final auth = ref.watch(authSessionProvider);
    final staff = auth.context?.staffProfile;
    final canUploadAttachments = canEdit && staff != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Treatment', style: AppTypography.h2(context)),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Plan investigations, prescribe treatments, and attach supporting documents.',
          style: AppTypography.bodySm(context).copyWith(color: context.appColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space6),
        AppFormField(
          id: 'treatment-notes',
          label: 'Treatment notes',
          hint: 'Clinical reasoning, patient education, and follow-up instructions.',
          child: AppRichTextEditor(
            id: 'treatment-notes-input',
            controller: _planController,
            focusNode: _planFocusNode,
            placeholder: 'Rest, hydration, return if symptoms worsen…',
            minLines: 3,
            autoGrow: true,
            disabled: !canEdit,
            readOnly: !canEdit,
            onChanged: canEdit
                ? (plainText, richDelta) {
                    if (_syncingFromState) {
                      return;
                    }
                    notifier.updatePlan(plainText, richDelta: richDelta);
                  }
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        AppFormField(
          id: 'investigations',
          label: 'Investigations needed',
          helperText: 'Add each test via the dialog with any relevant clinical notes.',
          child: VisitInvestigationsEditor(
            entries: investigations,
            canEdit: canEdit,
            onCreate: ({required name, note, investigationId}) =>
                notifier.stageCreateInvestigation(name: name, note: note, investigationId: investigationId),
            onUpdate: (id, {required name, note, investigationId}) => notifier.stageUpdateInvestigation(
              investigationLineId: id,
              name: name,
              note: note,
              investigationId: investigationId,
              updateInvestigationId: true,
            ),
            onArchive: notifier.stageArchiveInvestigation,
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        AppFormField(
          id: 'treatment-plan',
          label: 'Treatment plan',
          helperText: 'Add each prescription via the dialog with dosage, frequency, and duration.',
          child: VisitTreatmentPlanEditor(
            entries: treatmentPlans,
            canEdit: canEdit,
            onCreate: ({required medicationName, medicationId, dosage, frequency, duration, notes}) =>
                notifier.stageCreateTreatmentPlan(
                  medicationName: medicationName,
                  medicationId: medicationId,
                  dosage: dosage,
                  frequency: frequency,
                  duration: duration,
                  notes: notes,
                ),
            onUpdate: (id, {medicationName, medicationId, dosage, frequency, duration, notes}) =>
                notifier.stageUpdateTreatmentPlan(
                  treatmentPlanId: id,
                  medicationName: medicationName,
                  medicationId: medicationId,
                  dosage: dosage,
                  frequency: frequency,
                  duration: duration,
                  notes: notes,
                ),
            onArchive: notifier.stageArchiveTreatmentPlan,
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        AppFormField(
          id: 'documents',
          label: 'Attachments',
          helperText: 'Upload lab results, referrals, or other visit documents.',
          child: VisitAttachmentsEditor(
            attachments: attachments,
            canEdit: canUploadAttachments,
            uploadedBy: staff?.staffMemberId ?? '',
            uploadedByName: staff?.fullName,
            onStage: ({required pick, required label, required uploadedBy, uploadedByName}) => notifier.stageAttachment(
              pick: pick,
              label: label,
              uploadedBy: uploadedBy,
              uploadedByName: uploadedByName,
            ),
            onDelete: notifier.stageDeleteAttachment,
          ),
        ),
      ],
    );
  }
}
