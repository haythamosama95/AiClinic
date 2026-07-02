import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_text_field.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Clinical note editor with optional section filtering for encounter phases (014).
class ClinicalNoteEditor extends ConsumerWidget {
  const ClinicalNoteEditor({
    required this.visitId,
    required this.state,
    required this.canEdit,
    this.sections,
    this.showStaleBanner = true,
    this.showSaveBar = true,
    this.showEditButton = false,
    this.showSectionHeaders = true,
    this.expandField = false,
    this.useRichTextParagraph = false,
    this.removeBorder = false,
    this.toolbarLeading,
    this.emptyStateIcon,
    this.emptyStateText,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final Set<ClinicalNoteSection>? sections;
  final bool showStaleBanner;
  final bool showSaveBar;
  final bool showEditButton;
  final bool showSectionHeaders;
  final bool expandField;

  /// Uses [AppParagraphField] rich-text mode with a transparent background.
  final bool useRichTextParagraph;

  /// When `true`, omits the rich-text field border (see [AppParagraphField.removeBorder]).
  final bool removeBorder;

  /// Pinned to the left of the rich-text toolbar row when [useRichTextParagraph] is true.
  final Widget? toolbarLeading;

  /// Shown centered in the rich-text field while empty (see [AppParagraphField]).
  final IconData? emptyStateIcon;
  final String? emptyStateText;

  Set<ClinicalNoteSection> get _visibleSections => sections ?? ClinicalNoteSection.values.toSet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canEdit) {
      return _ReadOnlyClinicalNote(
        state: state,
        sections: _visibleSections,
        showSectionHeaders: showSectionHeaders,
        expandField: expandField,
      );
    }
    if (state.noteEditMode == DocumentationEditMode.readOnly) {
      return _ReadOnlyClinicalNote(
        state: state,
        sections: _visibleSections,
        showEditButton: showEditButton,
        showSectionHeaders: showSectionHeaders,
        expandField: expandField,
        onEdit: () => ref.read(visitDocumentationProvider(visitId).notifier).enterEditMode(),
      );
    }
    return _EditableClinicalNote(
      visitId: visitId,
      state: state,
      sections: _visibleSections,
      showStaleBanner: showStaleBanner,
      showSaveBar: showSaveBar,
      showSectionHeaders: showSectionHeaders,
      expandField: expandField,
      useRichTextParagraph: useRichTextParagraph,
      removeBorder: removeBorder,
      toolbarLeading: toolbarLeading,
      emptyStateIcon: emptyStateIcon,
      emptyStateText: emptyStateText,
    );
  }
}

class _EditableClinicalNote extends ConsumerStatefulWidget {
  const _EditableClinicalNote({
    required this.visitId,
    required this.state,
    required this.sections,
    required this.showStaleBanner,
    required this.showSaveBar,
    required this.showSectionHeaders,
    required this.expandField,
    required this.useRichTextParagraph,
    required this.removeBorder,
    this.toolbarLeading,
    this.emptyStateIcon,
    this.emptyStateText,
  });

  final String visitId;
  final VisitDocumentationState state;
  final Set<ClinicalNoteSection> sections;
  final bool showStaleBanner;
  final bool showSaveBar;
  final bool showSectionHeaders;
  final bool expandField;
  final bool useRichTextParagraph;
  final bool removeBorder;
  final Widget? toolbarLeading;
  final IconData? emptyStateIcon;
  final String? emptyStateText;

  @override
  ConsumerState<_EditableClinicalNote> createState() => _EditableClinicalNoteState();
}

class _EditableClinicalNoteState extends ConsumerState<_EditableClinicalNote> {
  late final Map<ClinicalNoteSection, TextEditingController> _controllers;
  Map<ClinicalNoteSection, QuillController>? _quillControllers;
  late final VoidCallback _flushToNotifier;
  VisitDocumentationNotifier? _documentationNotifier;
  var _flushRegistered = false;

  @override
  void initState() {
    super.initState();
    _flushToNotifier = _flushSectionsToNotifier;
    _controllers = {
      for (final section in ClinicalNoteSection.values)
        section: TextEditingController(text: _textForSection(widget.state, section)),
    };
    if (widget.useRichTextParagraph) {
      _quillControllers = {
        for (final section in widget.sections)
          section: _quillFromDraft(widget.state.richTextDrafts[section], _textForSection(widget.state, section)),
      };
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_flushRegistered) {
      return;
    }
    _flushRegistered = true;
    _documentationNotifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    _documentationNotifier!.registerClinicalNoteFlush(_flushToNotifier);
  }

  @override
  void didUpdateWidget(covariant _EditableClinicalNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.saveStatus == DocumentationSaveStatus.stale &&
        widget.state.saveStatus != DocumentationSaveStatus.stale) {
      _syncControllersFromState(widget.state);
    }
  }

  void _syncControllersFromState(VisitDocumentationState state) {
    for (final section in ClinicalNoteSection.values) {
      _controllers[section]!.text = _textForSection(state, section);
    }
    if (_quillControllers != null) {
      for (final section in widget.sections) {
        _setQuillFromDraft(
          _quillControllers![section]!,
          state.richTextDrafts[section],
          _textForSection(state, section),
        );
      }
    }
  }

  @override
  void dispose() {
    _documentationNotifier?.unregisterClinicalNoteFlush(_flushToNotifier);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final controller in _quillControllers?.values ?? const <QuillController>[]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _flushSectionsToNotifier() {
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    for (final section in widget.sections) {
      final quillController = _quillControllers?[section];
      if (widget.useRichTextParagraph && quillController != null) {
        final document = quillController.document;
        _onChangedForSection(notifier, section, true)(
          _plainTextFromQuillDocument(document),
          _richDeltaFromDocument(document),
        );
        continue;
      }
      _onChangedForSection(notifier, section, false)(_controllers[section]!.text, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final isSaving = state.saveStatus == DocumentationSaveStatus.saving;
    final orderedSections = ClinicalNoteSection.values.where(widget.sections.contains).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showStaleBanner && state.saveStatus == DocumentationSaveStatus.stale) ...[
          AppAlert(
            key: const Key('clinical_note_stale_banner'),
            title: state.errorMessage ?? 'This visit note was updated elsewhere. Reload and try again.',
            variant: AppAlertVariant.destructive,
            icon: const Icon(Icons.warning_amber_outlined),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const Key('clinical_note_reload_button'),
              label: 'Reload',
              variant: AppButtonVariant.outline,
              onPressed: isSaving ? null : () => notifier.reloadAfterStale(),
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
        ],
        if (widget.expandField && orderedSections.length == 1)
          Expanded(
            child: _ClinicalNoteField(
              key: Key('clinical_note_${orderedSections.first.name}'),
              abbr: orderedSections.first.abbr,
              label: orderedSections.first.label,
              controller: _controllers[orderedSections.first]!,
              quillController: _quillControllers?[orderedSections.first],
              useRichTextParagraph: widget.useRichTextParagraph,
              removeBorder: widget.removeBorder,
              enabled: !isSaving,
              onChanged: _onChangedForSection(notifier, orderedSections.first, widget.useRichTextParagraph),
              showSectionHeader: widget.showSectionHeaders,
              expand: true,
              toolbarLeading: widget.toolbarLeading,
              emptyStateIcon: widget.emptyStateIcon,
              emptyStateText: widget.emptyStateText,
            ),
          )
        else
          for (var i = 0; i < orderedSections.length; i++) ...[
            _ClinicalNoteField(
              key: Key('clinical_note_${orderedSections[i].name}'),
              abbr: orderedSections[i].abbr,
              label: orderedSections[i].label,
              controller: _controllers[orderedSections[i]]!,
              quillController: _quillControllers?[orderedSections[i]],
              useRichTextParagraph: widget.useRichTextParagraph,
              removeBorder: widget.removeBorder,
              enabled: !isSaving,
              onChanged: _onChangedForSection(notifier, orderedSections[i], widget.useRichTextParagraph),
              showDivider: i < orderedSections.length - 1,
              showSectionHeader: widget.showSectionHeaders,
              toolbarLeading: i == 0 ? widget.toolbarLeading : null,
              emptyStateIcon: widget.emptyStateIcon,
              emptyStateText: widget.emptyStateText,
            ),
          ],
        if (widget.showSaveBar) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.visitTheme.tile,
              borderRadius: BorderRadius.circular(context.visitTheme.tileRadius),
              border: Border.all(color: context.visitTheme.hairlineSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
              child: Row(
                children: [
                  if (state.saveStatus == DocumentationSaveStatus.saved)
                    Row(
                      key: const Key('clinical_note_saved_label'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 15, color: context.visitTheme.pulseDeep),
                        const SizedBox(width: SpacingTokens.xs),
                        Text(
                          'Saved',
                          style: context.visitTheme.bodyStrong(color: context.visitTheme.pulseDeep, size: 13),
                        ),
                      ],
                    ),
                  if (state.saveStatus == DocumentationSaveStatus.error && state.errorMessage != null)
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        key: const Key('clinical_note_error_label'),
                        style: context.visitTheme.caption(color: context.visitTheme.danger),
                      ),
                    )
                  else
                    const Spacer(),
                  AppButton(
                    key: const Key('clinical_note_save_button'),
                    label: isSaving ? 'Saving…' : 'Save clinical note',
                    icon: const Icon(Icons.save_outlined, size: 18),
                    isLoading: isSaving,
                    onPressed: isSaving ? null : () => notifier.save(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void Function(String plainText, List<dynamic>? richDelta) _onChangedForSection(
    VisitDocumentationNotifier notifier,
    ClinicalNoteSection section,
    bool useRichText,
  ) {
    return (plainText, richDelta) => switch (section) {
      ClinicalNoteSection.complaint => notifier.updateComplaint(plainText, richDelta: useRichText ? richDelta : null),
      ClinicalNoteSection.history => notifier.updateHistory(plainText, richDelta: useRichText ? richDelta : null),
      ClinicalNoteSection.examination => notifier.updateExamination(
        plainText,
        richDelta: useRichText ? richDelta : null,
      ),
      ClinicalNoteSection.diagnosis => notifier.updateDiagnosis(plainText, richDelta: useRichText ? richDelta : null),
      ClinicalNoteSection.plan => notifier.updatePlan(plainText, richDelta: useRichText ? richDelta : null),
    };
  }
}

class _ReadOnlyClinicalNote extends StatelessWidget {
  const _ReadOnlyClinicalNote({
    required this.state,
    required this.sections,
    this.showEditButton = false,
    this.showSectionHeaders = true,
    this.expandField = false,
    this.onEdit,
  });

  final VisitDocumentationState state;
  final Set<ClinicalNoteSection> sections;
  final bool showEditButton;
  final bool showSectionHeaders;
  final bool expandField;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final orderedSections = ClinicalNoteSection.values.where(sections.contains).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expandField && orderedSections.length == 1)
          Expanded(
            child: SingleChildScrollView(
              child: _ReadOnlySection(
                key: Key('visit_detail_${orderedSections.first.name}'),
                abbr: orderedSections.first.abbr,
                label: orderedSections.first.label,
                value: _textForSection(state, orderedSections.first),
                showSectionHeader: showSectionHeaders,
              ),
            ),
          )
        else
          for (final section in orderedSections)
            _ReadOnlySection(
              key: Key('visit_detail_${section.name}'),
              abbr: section.abbr,
              label: section.label,
              value: _textForSection(state, section),
              showSectionHeader: showSectionHeaders,
            ),
        if (showEditButton && onEdit != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const Key('clinical_note_edit_button'),
              label: 'Edit clinical note',
              size: AppFieldSize.sm,
              variant: AppButtonVariant.ghost,
              icon: Icon(Icons.edit_outlined, size: 18, color: context.visitTheme.pulse),
              onPressed: onEdit,
            ),
          ),
        ],
      ],
    );
  }
}

class _ReadOnlySection extends StatelessWidget {
  const _ReadOnlySection({
    required this.abbr,
    required this.label,
    required this.value,
    this.showSectionHeader = true,
    super.key,
  });

  final String abbr;
  final String label;
  final String value;
  final bool showSectionHeader;

  @override
  Widget build(BuildContext context) {
    if (!showSectionHeader) {
      final theme = context.visitTheme;
      final display = value.trim().isEmpty ? '—' : value.trim();
      final isEmpty = value.trim().isEmpty;

      return Text(display, style: theme.body(color: isEmpty ? theme.mutedInk : theme.ink));
    }

    return VisitDetailField(label: label, value: value, abbr: abbr);
  }
}

class _ClinicalNoteField extends StatelessWidget {
  const _ClinicalNoteField({
    required this.abbr,
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.enabled,
    this.quillController,
    this.useRichTextParagraph = false,
    this.removeBorder = false,
    this.showDivider = true,
    this.showSectionHeader = true,
    this.expand = false,
    this.toolbarLeading,
    this.emptyStateIcon,
    this.emptyStateText,
    super.key,
  });

  final String abbr;
  final String label;
  final TextEditingController controller;
  final QuillController? quillController;
  final bool useRichTextParagraph;
  final bool removeBorder;
  final void Function(String plainText, List<dynamic>? richDelta) onChanged;
  final bool enabled;
  final bool showDivider;
  final bool showSectionHeader;
  final bool expand;
  final Widget? toolbarLeading;
  final IconData? emptyStateIcon;
  final String? emptyStateText;

  Widget _richParagraphField({required bool fitParent}) {
    return AppParagraphField(
      richText: true,
      transparentBackground: true,
      removeBorder: removeBorder,
      fitParent: fitParent,
      quillController: quillController,
      enabled: enabled,
      minLines: 3,
      toolbarLeading: toolbarLeading,
      emptyStateIcon: emptyStateIcon,
      emptyStateText: emptyStateText,
      onDocumentChanged: (document) =>
          onChanged(_plainTextFromQuillDocument(document), _richDeltaFromDocument(document)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    if (!showSectionHeader) {
      if (useRichTextParagraph && quillController != null) {
        if (expand) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              if (!height.isFinite) {
                return _richParagraphField(fitParent: false);
              }
              return SizedBox(height: height, child: _richParagraphField(fitParent: true));
            },
          );
        }
        return _richParagraphField(fitParent: false);
      }

      return VisitTextInput(
        controller: controller,
        enabled: enabled,
        minLines: expand ? null : 3,
        maxLines: expand ? null : 8,
        expands: expand,
        onChanged: (value) => onChanged(value, null),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VisitMarginAbbr(letter: abbr),
              const SizedBox(width: SpacingTokens.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label.toUpperCase(), style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
                    const SizedBox(height: SpacingTokens.xs + 1),
                    VisitTextInput(
                      controller: controller,
                      enabled: enabled,
                      minLines: 3,
                      maxLines: 8,
                      onChanged: (value) => onChanged(value, null),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showDivider) ...[const SizedBox(height: SpacingTokens.md), Divider(height: 1, color: theme.hairlineSoft)],
        ],
      ),
    );
  }
}

String _textForSection(VisitDocumentationState state, ClinicalNoteSection section) => switch (section) {
  ClinicalNoteSection.complaint => state.complaint,
  ClinicalNoteSection.history => state.history,
  ClinicalNoteSection.examination => state.examination,
  ClinicalNoteSection.diagnosis => state.diagnosis,
  ClinicalNoteSection.plan => state.plan,
};

String _plainTextFromQuillDocument(Document document) {
  final raw = document.toPlainText();
  if (raw.endsWith('\n')) {
    return raw.substring(0, raw.length - 1);
  }
  return raw;
}

QuillController _quillFromDraft(List<dynamic>? deltaJson, String plainText) {
  if (deltaJson != null && deltaJson.isNotEmpty) {
    return QuillController(document: Document.fromJson(deltaJson), selection: const TextSelection.collapsed(offset: 0));
  }
  return _quillFromPlainText(plainText);
}

void _setQuillFromDraft(QuillController controller, List<dynamic>? deltaJson, String plainText) {
  if (deltaJson != null && deltaJson.isNotEmpty) {
    controller.document = Document.fromJson(deltaJson);
    return;
  }
  _setQuillPlainText(controller, plainText);
}

List<dynamic>? _richDeltaFromDocument(Document document) {
  final delta = document.toDelta().toJson();
  if (delta.length == 1) {
    final first = delta.first as Map;
    if (first['insert'] == '\n' && first['attributes'] == null) {
      return null;
    }
  }
  return delta;
}

QuillController _quillFromPlainText(String text) {
  final controller = QuillController.basic();
  if (text.isNotEmpty) {
    _setQuillPlainText(controller, text);
  }
  return controller;
}

void _setQuillPlainText(QuillController controller, String text) {
  final current = controller.plainTextEditingValue.text;
  final deleteLen = current.isEmpty ? 0 : current.length - 1;
  controller.replaceText(0, deleteLen, text, TextSelection.collapsed(offset: text.length));
}
