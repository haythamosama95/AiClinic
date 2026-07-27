import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_rich_text_editor.dart';
import 'package:ai_clinic/core/ui/rich_text/rich_text_delta_utils.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Single clinical-note editor with Quill controller lifecycle and notifier sync.
class ClinicalNoteField extends ConsumerStatefulWidget {
  const ClinicalNoteField({
    required this.visitId,
    required this.section,
    required this.fieldId,
    required this.editorId,
    required this.label,
    this.hint,
    this.placeholder,
    this.requiredMark = false,
    this.canEdit = true,
    this.minLines = 6,
    super.key,
  });

  final String visitId;
  final ClinicalNoteSection section;
  final String fieldId;
  final String editorId;
  final String label;
  final String? hint;
  final String? placeholder;
  final bool requiredMark;
  final bool canEdit;
  final int minLines;

  @override
  ConsumerState<ClinicalNoteField> createState() => _ClinicalNoteFieldState();
}

class _ClinicalNoteFieldState extends ConsumerState<ClinicalNoteField> {
  late final QuillController _controller;
  late final FocusNode _focusNode;
  late final VoidCallback _flush;
  VisitDocumentationNotifier? _documentationNotifier;
  var _flushRegistered = false;
  var _syncingFromState = false;

  @override
  void initState() {
    super.initState();
    _controller = QuillController.basic();
    _focusNode = FocusNode();
    _flush = () => _flushController(_controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncFromProvider();
      if (widget.canEdit) {
        _registerFlushCallback(ref.read(visitDocumentationProvider(widget.visitId).notifier));
      }
    });
  }

  @override
  void dispose() {
    _unregisterFlushCallback();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _registerFlushCallback(VisitDocumentationNotifier notifier) {
    if (_flushRegistered) {
      return;
    }
    _documentationNotifier = notifier;
    notifier.registerClinicalNoteFlush(_flush);
    _flushRegistered = true;
  }

  void _unregisterFlushCallback() {
    if (!_flushRegistered) {
      return;
    }
    _documentationNotifier?.unregisterClinicalNoteFlush(_flush);
    _documentationNotifier = null;
    _flushRegistered = false;
  }

  void _syncFromProvider() {
    final state = ref.read(visitDocumentationProvider(widget.visitId)).value;
    if (state != null) {
      _syncFromState(state);
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
    _pushDraft(notifier, plainText, richDelta);
  }

  void _pushDraft(VisitDocumentationNotifier notifier, String plainText, List<dynamic>? richDelta) {
    switch (widget.section) {
      case ClinicalNoteSection.complaint:
        notifier.updateComplaint(plainText, richDelta: richDelta);
      case ClinicalNoteSection.history:
        notifier.updateHistory(plainText, richDelta: richDelta);
      case ClinicalNoteSection.examination:
        notifier.updateExamination(plainText, richDelta: richDelta);
      case ClinicalNoteSection.diagnosis:
        notifier.updateDiagnosis(plainText, richDelta: richDelta);
      case ClinicalNoteSection.plan:
        notifier.updatePlan(plainText, richDelta: richDelta);
    }
  }

  void _syncFromState(VisitDocumentationState state) {
    _syncQuillController(
      _controller,
      _focusNode,
      state.richTextDrafts[widget.section],
      _plainTextForSection(state),
    );
  }

  String _plainTextForSection(VisitDocumentationState state) {
    return switch (widget.section) {
      ClinicalNoteSection.complaint => state.complaint,
      ClinicalNoteSection.history => state.history,
      ClinicalNoteSection.examination => state.examination,
      ClinicalNoteSection.diagnosis => state.diagnosis,
      ClinicalNoteSection.plan => state.plan,
    };
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

    final canEdit = widget.canEdit;
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);

    return AppFormField(
      id: widget.fieldId,
      label: widget.label,
      requiredMark: widget.requiredMark,
      hint: widget.hint,
      child: AppRichTextEditor(
        id: widget.editorId,
        controller: _controller,
        focusNode: _focusNode,
        placeholder: widget.placeholder,
        minLines: widget.minLines,
        autoGrow: true,
        disabled: !canEdit,
        readOnly: !canEdit,
        onChanged: canEdit
            ? (plainText, richDelta) {
                if (_syncingFromState) {
                  return;
                }
                _pushDraft(notifier, plainText, richDelta);
              }
            : null,
      ),
    );
  }
}
