import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/rich_text_draft_utils.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_vital_signs_editor.dart';

/// Findings step — physical examination, vital signs, and diagnosis.
class VisitFindingsSection extends ConsumerStatefulWidget {
  const VisitFindingsSection({required this.visitId, required this.canEdit, super.key});

  final String visitId;
  final bool canEdit;

  @override
  ConsumerState<VisitFindingsSection> createState() => _VisitFindingsSectionState();
}

class _VisitFindingsSectionState extends ConsumerState<VisitFindingsSection> {
  late final QuillController _examinationController;
  late final QuillController _diagnosisController;
  late final FocusNode _examinationFocusNode;
  late final FocusNode _diagnosisFocusNode;
  late final VoidCallback _examinationFlush;
  late final VoidCallback _diagnosisFlush;
  VisitDocumentationNotifier? _documentationNotifier;
  var _flushRegistered = false;
  var _syncingFromState = false;

  @override
  void initState() {
    super.initState();
    _examinationController = QuillController.basic();
    _diagnosisController = QuillController.basic();
    _examinationFocusNode = FocusNode();
    _diagnosisFocusNode = FocusNode();
    _examinationFlush = () => _flushController(ClinicalNoteSection.examination, _examinationController);
    _diagnosisFlush = () => _flushController(ClinicalNoteSection.diagnosis, _diagnosisController);

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
    _examinationFocusNode.dispose();
    _diagnosisFocusNode.dispose();
    _examinationController.dispose();
    _diagnosisController.dispose();
    super.dispose();
  }

  void _registerFlushCallbacks(VisitDocumentationNotifier notifier) {
    if (_flushRegistered) {
      return;
    }
    _documentationNotifier = notifier;
    notifier
      ..registerClinicalNoteFlush(_examinationFlush)
      ..registerClinicalNoteFlush(_diagnosisFlush);
    _flushRegistered = true;
  }

  void _unregisterFlushCallbacks() {
    if (!_flushRegistered) {
      return;
    }
    _documentationNotifier
      ?..unregisterClinicalNoteFlush(_examinationFlush)
      ..unregisterClinicalNoteFlush(_diagnosisFlush);
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
      case ClinicalNoteSection.examination:
        notifier.updateExamination(plainText, richDelta: richDelta);
      case ClinicalNoteSection.diagnosis:
        notifier.updateDiagnosis(plainText, richDelta: richDelta);
      case ClinicalNoteSection.complaint:
      case ClinicalNoteSection.history:
      case ClinicalNoteSection.plan:
        break;
    }
  }

  void _syncControllers(VisitDocumentationState state) {
    _syncQuillController(
      _examinationController,
      _examinationFocusNode,
      state.richTextDrafts[ClinicalNoteSection.examination],
      state.examination,
    );
    _syncQuillController(
      _diagnosisController,
      _diagnosisFocusNode,
      state.richTextDrafts[ClinicalNoteSection.diagnosis],
      state.diagnosis,
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
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final canEdit = widget.canEdit;
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
        AppFormField(
          id: 'physical-examination',
          label: 'Physical examination',
          hint: 'Objective findings from the clinical examination.',
          child: AppRichTextEditor(
            id: 'physical-examination-input',
            controller: _examinationController,
            focusNode: _examinationFocusNode,
            placeholder: 'General appearance, systems examined, notable findings…',
            minLines: 6,
            autoGrow: true,
            disabled: !canEdit,
            readOnly: !canEdit,
            onChanged: canEdit
                ? (plainText, richDelta) {
                    if (_syncingFromState) {
                      return;
                    }
                    notifier.updateExamination(plainText, richDelta: richDelta);
                  }
                : null,
          ),
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
        AppFormField(
          id: 'diagnosis',
          label: 'Diagnosis',
          requiredMark: true,
          hint: 'Primary and secondary diagnoses for this encounter.',
          child: AppRichTextEditor(
            id: 'diagnosis-input',
            controller: _diagnosisController,
            focusNode: _diagnosisFocusNode,
            placeholder: 'e.g. Acute upper respiratory infection (J06.9)…',
            minLines: 6,
            autoGrow: true,
            disabled: !canEdit,
            readOnly: !canEdit,
            onChanged: canEdit
                ? (plainText, richDelta) {
                    if (_syncingFromState) {
                      return;
                    }
                    notifier.updateDiagnosis(plainText, richDelta: richDelta);
                  }
                : null,
          ),
        ),
      ],
    );
  }
}
