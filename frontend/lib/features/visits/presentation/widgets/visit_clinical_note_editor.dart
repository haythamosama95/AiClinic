import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Placeholder copy for clinical note sections (013 US1).
String clinicalNotePlaceholder(ClinicalNoteSection section) => switch (section) {
  ClinicalNoteSection.complaint => "The patient's main reason for the visit.",
  ClinicalNoteSection.history => 'History of present illness.',
  ClinicalNoteSection.examination => 'Physical examination findings.',
  ClinicalNoteSection.diagnosis => 'Clinical assessment or diagnosis.',
  ClinicalNoteSection.plan => 'Treatment plan, follow-up instructions, and patient advice.',
};

/// Rich-text clinical note editor for encounter phases.
///
/// Registers flush callbacks with [VisitDocumentationNotifier] so Quill content
/// is synced before submit validation.
class VisitClinicalNoteEditor extends ConsumerStatefulWidget {
  const VisitClinicalNoteEditor({
    required this.visitId,
    required this.state,
    required this.sections,
    required this.canEdit,
    this.showStaleBanner = true,
    this.showSectionHeaders = true,
    this.expandSingleSection = false,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final Set<ClinicalNoteSection> sections;
  final bool canEdit;
  final bool showStaleBanner;
  final bool showSectionHeaders;
  final bool expandSingleSection;

  @override
  ConsumerState<VisitClinicalNoteEditor> createState() => _VisitClinicalNoteEditorState();
}

class _VisitClinicalNoteEditorState extends ConsumerState<VisitClinicalNoteEditor> {
  final Map<ClinicalNoteSection, AppRichTextEditorController> _controllers = {};
  late final VoidCallback _flushCallback;
  VisitDocumentationNotifier? _notifier;
  var _flushRegistered = false;

  @override
  void initState() {
    super.initState();
    _flushCallback = _flushToNotifier;
    _initControllers();
  }

  void _initControllers() {
    for (final section in widget.sections) {
      final delta = widget.state.richTextDrafts[section];
      final initial = delta != null
          ? AppRichTextValue(delta)
          : _plainToValue(_plainForSection(widget.state, section));
      _controllers[section] = AppRichTextEditorController(initialValue: initial);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_flushRegistered) return;
    _flushRegistered = true;
    _notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    _notifier!.registerClinicalNoteFlush(_flushCallback);
  }

  @override
  void didUpdateWidget(covariant VisitClinicalNoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visitId != widget.visitId) {
      _notifier?.unregisterClinicalNoteFlush(_flushCallback);
      _notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
      _notifier!.registerClinicalNoteFlush(_flushCallback);
    }
    if (oldWidget.state.saveStatus == DocumentationSaveStatus.stale &&
        widget.state.saveStatus != DocumentationSaveStatus.stale) {
      _syncFromState(widget.state);
    }
    if (oldWidget.sections != widget.sections) {
      for (final section in widget.sections) {
        _controllers.putIfAbsent(
          section,
          () => AppRichTextEditorController(
            initialValue: _plainToValue(_plainForSection(widget.state, section)),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _notifier?.unregisterClinicalNoteFlush(_flushCallback);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncFromState(VisitDocumentationState state) {
    for (final section in widget.sections) {
      final controller = _controllers[section];
      if (controller == null) continue;
      final delta = state.richTextDrafts[section];
      controller.value = delta != null
          ? AppRichTextValue(delta)
          : _plainToValue(_plainForSection(state, section));
    }
  }

  void _flushToNotifier() {
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    for (final section in widget.sections) {
      final controller = _controllers[section];
      if (controller == null) continue;
      final value = controller.value;
      final plain = value.toPlainText();
      final delta = value.isEffectivelyEmpty ? null : value.deltaJson;
      _applyChange(notifier, section, plain, delta);
    }
  }

  void _applyChange(
    VisitDocumentationNotifier notifier,
    ClinicalNoteSection section,
    String plain,
    List<dynamic>? delta,
  ) {
    switch (section) {
      case ClinicalNoteSection.complaint:
        notifier.updateComplaint(plain, richDelta: delta);
      case ClinicalNoteSection.history:
        notifier.updateHistory(plain, richDelta: delta);
      case ClinicalNoteSection.examination:
        notifier.updateExamination(plain, richDelta: delta);
      case ClinicalNoteSection.diagnosis:
        notifier.updateDiagnosis(plain, richDelta: delta);
      case ClinicalNoteSection.plan:
        notifier.updatePlan(plain, richDelta: delta);
    }
  }

  bool get _readOnly {
    if (!widget.canEdit) return true;
    return widget.state.noteEditMode == DocumentationEditMode.readOnly;
  }

  bool get _isSaving => widget.state.saveStatus == DocumentationSaveStatus.saving;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final ordered = ClinicalNoteSection.values.where(widget.sections.contains).toList();
    final textDirection = Directionality.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showStaleBanner && state.saveStatus == DocumentationSaveStatus.stale) ...[
          AppAlert(
            variant: AppAlertVariant.danger,
            title: state.errorMessage ?? 'This visit note was updated elsewhere. Reload and try again.',
          ),
          const SizedBox(height: AppSpacing.s2),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(
              label: 'Reload',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              disabled: _isSaving,
              onPressed: () => notifier.reloadAfterStale(),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
        ],
        for (var i = 0; i < ordered.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s4),
          _SectionField(
            section: ordered[i],
            controller: _controllers[ordered[i]]!,
            readOnly: _readOnly,
            disabled: _isSaving,
            showHeader: widget.showSectionHeaders,
            expand: widget.expandSingleSection && ordered.length == 1,
            textDirection: textDirection,
            onChanged: (value) {
              final plain = value.toPlainText();
              final delta = value.isEffectivelyEmpty ? null : value.deltaJson;
              _applyChange(notifier, ordered[i], plain, delta);
            },
            onEnterEdit: _readOnly && widget.canEdit
                ? () => notifier.enterEditMode()
                : null,
          ),
        ],
      ],
    );
  }

  static String _plainForSection(VisitDocumentationState state, ClinicalNoteSection section) =>
      switch (section) {
        ClinicalNoteSection.complaint => state.complaint,
        ClinicalNoteSection.history => state.history,
        ClinicalNoteSection.examination => state.examination,
        ClinicalNoteSection.diagnosis => state.diagnosis,
        ClinicalNoteSection.plan => state.plan,
      };

  static AppRichTextValue _plainToValue(String plain) {
    if (plain.trim().isEmpty) return AppRichTextValue.empty;
    return AppRichTextValue([
      {'insert': '$plain\n'},
    ]);
  }
}

class _SectionField extends StatelessWidget {
  const _SectionField({
    required this.section,
    required this.controller,
    required this.readOnly,
    required this.disabled,
    required this.showHeader,
    required this.expand,
    required this.textDirection,
    required this.onChanged,
    this.onEnterEdit,
  });

  final ClinicalNoteSection section;
  final AppRichTextEditorController controller;
  final bool readOnly;
  final bool disabled;
  final bool showHeader;
  final bool expand;
  final TextDirection textDirection;
  final ValueChanged<AppRichTextValue> onChanged;
  final VoidCallback? onEnterEdit;

  @override
  Widget build(BuildContext context) {
    final editor = Directionality(
      textDirection: textDirection,
      child: showHeader
          ? AppFormField(
              label: section.label,
              child: AppRichTextEditor(
                controller: controller,
                readOnly: readOnly,
                disabled: disabled,
                placeholder: clinicalNotePlaceholder(section),
                minRows: expand ? 8 : 3,
                onChanged: readOnly ? null : onChanged,
              ),
            )
          : AppRichTextEditor(
              controller: controller,
              readOnly: readOnly,
              disabled: disabled,
              placeholder: clinicalNotePlaceholder(section),
              minRows: expand ? 8 : 3,
              onChanged: readOnly ? null : onChanged,
            ),
    );

    if (!expand) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          editor,
          if (onEnterEdit != null) ...[
            const SizedBox(height: AppSpacing.s2),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AppButton(
                label: 'Edit',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                onPressed: onEnterEdit,
              ),
            ),
          ],
        ],
      );
    }

    return Expanded(child: editor);
  }
}
