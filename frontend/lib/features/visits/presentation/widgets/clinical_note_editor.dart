import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
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
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final Set<ClinicalNoteSection>? sections;
  final bool showStaleBanner;
  final bool showSaveBar;
  final bool showEditButton;

  Set<ClinicalNoteSection> get _visibleSections => sections ?? ClinicalNoteSection.values.toSet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canEdit) {
      return _ReadOnlyClinicalNote(state: state, sections: _visibleSections);
    }
    if (state.noteEditMode == DocumentationEditMode.readOnly) {
      return _ReadOnlyClinicalNote(
        state: state,
        sections: _visibleSections,
        showEditButton: showEditButton,
        onEdit: () => ref.read(visitDocumentationProvider(visitId).notifier).enterEditMode(),
      );
    }
    return _EditableClinicalNote(
      visitId: visitId,
      state: state,
      sections: _visibleSections,
      showStaleBanner: showStaleBanner,
      showSaveBar: showSaveBar,
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
  });

  final String visitId;
  final VisitDocumentationState state;
  final Set<ClinicalNoteSection> sections;
  final bool showStaleBanner;
  final bool showSaveBar;

  @override
  ConsumerState<_EditableClinicalNote> createState() => _EditableClinicalNoteState();
}

class _EditableClinicalNoteState extends ConsumerState<_EditableClinicalNote> {
  late final Map<ClinicalNoteSection, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final section in ClinicalNoteSection.values)
        section: TextEditingController(text: _textForSection(widget.state, section)),
    };
  }

  @override
  void didUpdateWidget(covariant _EditableClinicalNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.saveStatus == DocumentationSaveStatus.stale &&
        widget.state.saveStatus != DocumentationSaveStatus.stale) {
      for (final section in ClinicalNoteSection.values) {
        _controllers[section]!.text = _textForSection(widget.state, section);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
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
        for (var i = 0; i < orderedSections.length; i++) ...[
          _ClinicalNoteField(
            key: Key('clinical_note_${orderedSections[i].name}'),
            abbr: orderedSections[i].abbr,
            label: orderedSections[i].label,
            hintText: orderedSections[i].hasHint ? orderedSections[i].hint : null,
            controller: _controllers[orderedSections[i]]!,
            enabled: !isSaving,
            onChanged: _onChangedForSection(notifier, orderedSections[i]),
            showDivider: i < orderedSections.length - 1,
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

  ValueChanged<String> _onChangedForSection(VisitDocumentationNotifier notifier, ClinicalNoteSection section) {
    return switch (section) {
      ClinicalNoteSection.complaint => notifier.updateComplaint,
      ClinicalNoteSection.history => notifier.updateHistory,
      ClinicalNoteSection.examination => notifier.updateExamination,
      ClinicalNoteSection.diagnosis => notifier.updateDiagnosis,
      ClinicalNoteSection.plan => notifier.updatePlan,
    };
  }
}

class _ReadOnlyClinicalNote extends StatelessWidget {
  const _ReadOnlyClinicalNote({required this.state, required this.sections, this.showEditButton = false, this.onEdit});

  final VisitDocumentationState state;
  final Set<ClinicalNoteSection> sections;
  final bool showEditButton;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final orderedSections = ClinicalNoteSection.values.where(sections.contains).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in orderedSections)
          _ReadOnlySection(
            key: Key('visit_detail_${section.name}'),
            abbr: section.abbr,
            label: section.label,
            value: _textForSection(state, section),
          ),
        if (showEditButton && onEdit != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const Key('clinical_note_edit_button'),
              label: 'Edit clinical note',
              variant: AppButtonVariant.outline,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
            ),
          ),
        ],
      ],
    );
  }
}

class _ReadOnlySection extends StatelessWidget {
  const _ReadOnlySection({required this.abbr, required this.label, required this.value, super.key});

  final String abbr;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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
    this.hintText,
    this.showDivider = true,
    super.key,
  });

  final String abbr;
  final String label;
  final String? hintText;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

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
                    AppTextInput(
                      hintText: hintText,
                      controller: controller,
                      enabled: enabled,
                      minLines: 3,
                      maxLines: 8,
                      onChanged: onChanged,
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
