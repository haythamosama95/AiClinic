import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Shared clinical note rich-text block for visit documentation sections.
///
/// Stagger enter is applied by a parent [VisitStagger] when present; this widget
/// is a plain form-field block otherwise.
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
  late final AppRichTextEditorController _editorController;
  late final VoidCallback _flushCallback;

  @override
  void initState() {
    super.initState();
    _editorController = AppRichTextEditorController(
      initialValue: AppRichTextValue.fromDraft(widget.richDelta, widget.value),
    );
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
    final doc = ref.read(visitDocumentationProvider(widget.visitId)).value;
    if (doc?.saveStatus == DocumentationSaveStatus.stale && oldWidget.value != widget.value) {
      _editorController.value = AppRichTextValue.fromDraft(widget.richDelta, widget.value);
    }
  }

  @override
  void dispose() {
    ref.read(visitDocumentationProvider(widget.visitId).notifier).unregisterClinicalNoteFlush(_flushCallback);
    _editorController.dispose();
    super.dispose();
  }

  void _flushToNotifier() {
    final value = _editorController.value;
    widget.onChanged(value.toPlainText(), value.nullableDelta);
  }

  void _handleChanged(AppRichTextValue value) {
    widget.onChanged(value.toPlainText(), value.nullableDelta);
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
        controller: _editorController,
        onChanged: widget.readOnly ? null : _handleChanged,
        minRows: widget.rows,
        placeholder: widget.placeholder,
        readOnly: widget.readOnly,
        disabled: widget.readOnly,
      ),
    );
  }
}
