import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Five-section clinical note editor with chart margin rail (013 US1).
class ClinicalNoteEditor extends ConsumerWidget {
  const ClinicalNoteEditor({required this.visitId, required this.state, required this.canEdit, super.key});

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canEdit) {
      return _ReadOnlyClinicalNote(state: state);
    }
    if (state.noteEditMode == DocumentationEditMode.readOnly) {
      return _ReadOnlyClinicalNote(
        state: state,
        showEditButton: true,
        onEdit: () => ref.read(visitDocumentationProvider(visitId).notifier).enterEditMode(),
      );
    }
    return _EditableClinicalNote(visitId: visitId, state: state);
  }
}

class _EditableClinicalNote extends ConsumerStatefulWidget {
  const _EditableClinicalNote({required this.visitId, required this.state});

  final String visitId;
  final VisitDocumentationState state;

  @override
  ConsumerState<_EditableClinicalNote> createState() => _EditableClinicalNoteState();
}

class _EditableClinicalNoteState extends ConsumerState<_EditableClinicalNote> {
  late final TextEditingController _complaint;
  late final TextEditingController _history;
  late final TextEditingController _examination;
  late final TextEditingController _diagnosis;
  late final TextEditingController _plan;

  @override
  void initState() {
    super.initState();
    _complaint = TextEditingController(text: widget.state.complaint);
    _history = TextEditingController(text: widget.state.history);
    _examination = TextEditingController(text: widget.state.examination);
    _diagnosis = TextEditingController(text: widget.state.diagnosis);
    _plan = TextEditingController(text: widget.state.plan);
  }

  @override
  void didUpdateWidget(covariant _EditableClinicalNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.saveStatus == DocumentationSaveStatus.stale &&
        widget.state.saveStatus != DocumentationSaveStatus.stale) {
      _complaint.text = widget.state.complaint;
      _history.text = widget.state.history;
      _examination.text = widget.state.examination;
      _diagnosis.text = widget.state.diagnosis;
      _plan.text = widget.state.plan;
    }
  }

  @override
  void dispose() {
    _complaint.dispose();
    _history.dispose();
    _examination.dispose();
    _diagnosis.dispose();
    _plan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final isSaving = state.saveStatus == DocumentationSaveStatus.saving;

    final fields =
        <
          ({
            String abbr,
            String label,
            String? hint,
            TextEditingController controller,
            void Function(String) onChanged,
            Key key,
          })
        >[
          (
            abbr: 'C',
            label: 'Complaint',
            hint: "The patient's main reason for the visit.",
            controller: _complaint,
            onChanged: notifier.updateComplaint,
            key: const Key('clinical_note_complaint'),
          ),
          (
            abbr: 'H',
            label: 'History',
            hint: null,
            controller: _history,
            onChanged: notifier.updateHistory,
            key: const Key('clinical_note_history'),
          ),
          (
            abbr: 'E',
            label: 'Examination',
            hint: 'Physical examination findings.',
            controller: _examination,
            onChanged: notifier.updateExamination,
            key: const Key('clinical_note_examination'),
          ),
          (
            abbr: 'D',
            label: 'Diagnosis',
            hint: 'Clinical assessment or diagnosis.',
            controller: _diagnosis,
            onChanged: notifier.updateDiagnosis,
            key: const Key('clinical_note_diagnosis'),
          ),
          (
            abbr: 'P',
            label: 'Plan',
            hint: 'Treatment plan, follow-up instructions, and patient advice.',
            controller: _plan,
            onChanged: notifier.updatePlan,
            key: const Key('clinical_note_plan'),
          ),
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.saveStatus == DocumentationSaveStatus.stale) ...[
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
        for (var i = 0; i < fields.length; i++) ...[
          _ClinicalNoteField(
            key: fields[i].key,
            abbr: fields[i].abbr,
            label: fields[i].label,
            hintText: fields[i].hint,
            controller: fields[i].controller,
            enabled: !isSaving,
            onChanged: fields[i].onChanged,
            showDivider: i < fields.length - 1,
          ),
        ],
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
    );
  }
}

class _ReadOnlyClinicalNote extends StatelessWidget {
  const _ReadOnlyClinicalNote({required this.state, this.showEditButton = false, this.onEdit});

  final VisitDocumentationState state;
  final bool showEditButton;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final values = [state.complaint, state.history, state.examination, state.diagnosis, state.plan];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < VisitPageTokens.clinicalSections.length; i++)
          _ReadOnlySection(
            abbr: VisitPageTokens.clinicalSections[i].abbr,
            label: VisitPageTokens.clinicalSections[i].label,
            value: values[i],
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
  const _ReadOnlySection({required this.abbr, required this.label, required this.value});

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
