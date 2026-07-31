import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/rich_text_draft_utils.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Shared clinical note rich-text block for visit documentation sections.
class VisitTextSection extends ConsumerStatefulWidget {
  const VisitTextSection({
    required this.visitId,
    required this.section,
    required this.id,
    required this.label,
    required this.value,
    required this.onChanged,
    this.richDelta,
    this.hint,
    this.required = false,
    this.rows = 3,
    this.placeholder,
    this.readOnly = false,
    super.key,
  });

  final String visitId;
  final ClinicalNoteSection section;
  final String id;
  final String label;
  final String? hint;
  final bool required;
  final String value;
  final List<dynamic>? richDelta;
  final void Function(String plainText, List<dynamic>? richDelta) onChanged;
  final int rows;
  final String? placeholder;
  final bool readOnly;

  @override
  ConsumerState<VisitTextSection> createState() => _VisitTextSectionState();
}

class _VisitTextSectionState extends ConsumerState<VisitTextSection> {
  late final QuillController _controller;
  late final FocusNode _focusNode;
  late final VoidCallback _flushCallback;
  var _syncingFromState = false;

  @override
  void initState() {
    super.initState();
    _controller = quillControllerFromDraft(widget.richDelta, widget.value, readOnly: widget.readOnly);
    _focusNode = FocusNode();
    _flushCallback = _flushToNotifier;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(visitDocumentationProvider(widget.visitId).notifier).registerClinicalNoteFlush(_flushCallback);
    });
  }

  @override
  void didUpdateWidget(covariant VisitTextSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readOnly != widget.readOnly) {
      _controller.readOnly = widget.readOnly;
    }
    if (_focusNode.hasFocus) {
      return;
    }
    final currentPlain = plainTextFromQuillDocument(_controller.document);
    final currentDelta = richDeltaFromQuillDocument(_controller.document);
    final targetDelta = richDeltaIsEffectivelyEmpty(widget.richDelta) ? null : widget.richDelta;
    if (currentPlain == widget.value && _deltaEquals(currentDelta, targetDelta)) {
      return;
    }
    _syncingFromState = true;
    try {
      setQuillControllerFromDraft(_controller, widget.richDelta, widget.value);
    } finally {
      _syncingFromState = false;
    }
  }

  @override
  void dispose() {
    ref.read(visitDocumentationProvider(widget.visitId).notifier).unregisterClinicalNoteFlush(_flushCallback);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
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

  void _flushToNotifier() {
    widget.onChanged(
      plainTextFromQuillDocument(_controller.document),
      richDeltaFromQuillDocument(_controller.document),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppFormField(
      id: widget.id,
      label: widget.label,
      requiredMark: widget.required,
      hint: widget.hint,
      child: AppRichTextEditor(
        id: widget.id,
        controller: _controller,
        focusNode: _focusNode,
        onChanged: widget.readOnly
            ? null
            : (plainText, richDelta) {
                if (_syncingFromState) {
                  return;
                }
                widget.onChanged(plainText, richDelta);
              },
        minLines: widget.rows,
        autoGrow: true,
        placeholder: widget.placeholder,
        readOnly: widget.readOnly,
        disabled: widget.readOnly,
      ),
    );
  }
}
