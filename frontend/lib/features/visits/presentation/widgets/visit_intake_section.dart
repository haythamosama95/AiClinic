import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/rich_text_draft_utils.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_medical_background_editor.dart';

/// Patient intake step — chief complaint, history, and medical background.
class VisitIntakeSection extends ConsumerStatefulWidget {
  const VisitIntakeSection({required this.visitId, required this.canEdit, super.key});

  final String visitId;
  final bool canEdit;

  @override
  ConsumerState<VisitIntakeSection> createState() => _VisitIntakeSectionState();
}

class _VisitIntakeSectionState extends ConsumerState<VisitIntakeSection> {
  late final QuillController _complaintController;
  late final QuillController _historyController;
  late final FocusNode _complaintFocusNode;
  late final FocusNode _historyFocusNode;
  late final VoidCallback _complaintFlush;
  late final VoidCallback _historyFlush;
  VisitDocumentationNotifier? _documentationNotifier;
  var _flushRegistered = false;
  var _syncingFromState = false;

  @override
  void initState() {
    super.initState();
    _complaintController = QuillController.basic();
    _historyController = QuillController.basic();
    _complaintFocusNode = FocusNode();
    _historyFocusNode = FocusNode();
    _complaintFlush = () => _flushController(ClinicalNoteSection.complaint, _complaintController);
    _historyFlush = () => _flushController(ClinicalNoteSection.history, _historyController);

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
    _complaintFocusNode.dispose();
    _historyFocusNode.dispose();
    _complaintController.dispose();
    _historyController.dispose();
    super.dispose();
  }

  void _registerFlushCallbacks(VisitDocumentationNotifier notifier) {
    if (_flushRegistered) {
      return;
    }
    _documentationNotifier = notifier;
    notifier
      ..registerClinicalNoteFlush(_complaintFlush)
      ..registerClinicalNoteFlush(_historyFlush);
    _flushRegistered = true;
  }

  void _unregisterFlushCallbacks() {
    if (!_flushRegistered) {
      return;
    }
    _documentationNotifier
      ?..unregisterClinicalNoteFlush(_complaintFlush)
      ..unregisterClinicalNoteFlush(_historyFlush);
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

  void _flushController(ClinicalNoteSection section, QuillController controller) {
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final plainText = plainTextFromQuillDocument(controller.document);
    final richDelta = richDeltaFromQuillDocument(controller.document);
    switch (section) {
      case ClinicalNoteSection.complaint:
        notifier.updateComplaint(plainText, richDelta: richDelta);
      case ClinicalNoteSection.history:
        notifier.updateHistory(plainText, richDelta: richDelta);
      case ClinicalNoteSection.examination:
      case ClinicalNoteSection.diagnosis:
      case ClinicalNoteSection.plan:
        break;
    }
  }

  void _syncControllers(VisitDocumentationState state) {
    _syncQuillController(
      _complaintController,
      _complaintFocusNode,
      state.richTextDrafts[ClinicalNoteSection.complaint],
      state.complaint,
    );
    _syncQuillController(
      _historyController,
      _historyFocusNode,
      state.richTextDrafts[ClinicalNoteSection.history],
      state.history,
    );
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

    final patientId = docState?.visit.patientId ?? '';
    final safetyAsync = patientId.isEmpty ? null : ref.watch(patientSafetyProvider(patientId));
    final baseSafety = safetyAsync?.value ?? const PatientSafetyContext();
    final effectiveSafety = docState?.effectivePatientSafety(baseSafety) ?? baseSafety;
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final canEdit = widget.canEdit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Patient intake', style: AppTypography.h2(context)),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Record the presenting complaint and relevant medical background.',
          style: AppTypography.bodySm(context).copyWith(color: context.appColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space6),
        AppFormField(
          id: 'chief-complaint',
          label: 'Chief complaint',
          requiredMark: true,
          hint: "The primary reason for today's visit, in the patient's own words.",
          child: AppRichTextEditor(
            id: 'chief-complaint-input',
            controller: _complaintController,
            focusNode: _complaintFocusNode,
            placeholder: 'e.g. Persistent cough for 5 days with mild fever…',
            minLines: 6,
            autoGrow: true,
            disabled: !canEdit,
            readOnly: !canEdit,
            onChanged: canEdit
                ? (plainText, richDelta) {
                    if (_syncingFromState) {
                      return;
                    }
                    notifier.updateComplaint(plainText, richDelta: richDelta);
                  }
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        AppFormField(
          id: 'history-of-present-illness',
          label: 'History of present illness',
          hint: 'Onset, duration, severity, aggravating and relieving factors.',
          child: AppRichTextEditor(
            id: 'history-of-present-illness-input',
            controller: _historyController,
            focusNode: _historyFocusNode,
            placeholder: 'Describe the timeline and progression of symptoms…',
            minLines: 6,
            autoGrow: true,
            disabled: !canEdit,
            readOnly: !canEdit,
            onChanged: canEdit
                ? (plainText, richDelta) {
                    if (_syncingFromState) {
                      return;
                    }
                    notifier.updateHistory(plainText, richDelta: richDelta);
                  }
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        VisitMedicalBackgroundEditor(
          chronicConditions: effectiveSafety.chronicConditions,
          allergies: effectiveSafety.allergies,
          currentMedications: effectiveSafety.currentMedications,
          canEdit: canEdit,
          onCreateCondition: (title, note) => notifier.stageCreateCondition(name: title, note: note),
          onUpdateCondition: (id, title, note) =>
              notifier.stageUpdateCondition(conditionId: id, name: title, note: note),
          onArchiveCondition: notifier.stageArchiveCondition,
          onCreateAllergy: (title, note) => notifier.stageCreateAllergy(substance: title, reaction: note),
          onUpdateAllergy: (id, title, note) =>
              notifier.stageUpdateAllergy(allergyId: id, substance: title, reaction: note),
          onArchiveAllergy: notifier.stageArchiveAllergy,
          onCreateMedication: (title, note) => notifier.stageCreateMedication(name: title, note: note),
          onUpdateMedication: (id, title, note) =>
              notifier.stageUpdateMedication(medicationRecordId: id, name: title, note: note),
          onArchiveMedication: notifier.stageArchiveMedication,
        ),
      ],
    );
  }
}
