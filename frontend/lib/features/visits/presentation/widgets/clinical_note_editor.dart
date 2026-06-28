import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Five-section clinical note editor with save and stale-conflict handling (013 US1).
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
    final colors = context.semanticColors;

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
        _ClinicalNoteField(
          key: const Key('clinical_note_complaint'),
          label: 'Complaint',
          hintText: "The patient's main reason for the visit.",
          controller: _complaint,
          enabled: !isSaving,
          onChanged: notifier.updateComplaint,
        ),
        _ClinicalNoteField(
          key: const Key('clinical_note_history'),
          label: 'History',
          controller: _history,
          enabled: !isSaving,
          onChanged: notifier.updateHistory,
        ),
        _ClinicalNoteField(
          key: const Key('clinical_note_examination'),
          label: 'Examination',
          hintText: 'Physical examination findings.',
          controller: _examination,
          enabled: !isSaving,
          onChanged: notifier.updateExamination,
        ),
        _ClinicalNoteField(
          key: const Key('clinical_note_diagnosis'),
          label: 'Diagnosis',
          hintText: 'Clinical assessment or diagnosis.',
          controller: _diagnosis,
          enabled: !isSaving,
          onChanged: notifier.updateDiagnosis,
        ),
        _ClinicalNoteField(
          key: const Key('clinical_note_plan'),
          label: 'Plan',
          hintText: 'Treatment plan, follow-up instructions, and patient advice.',
          controller: _plan,
          enabled: !isSaving,
          onChanged: notifier.updatePlan,
        ),
        if (state.saveStatus == DocumentationSaveStatus.saved)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: Text(
              'Saved',
              key: const Key('clinical_note_saved_label'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w600),
            ),
          ),
        if (state.saveStatus == DocumentationSaveStatus.error && state.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: Text(
              state.errorMessage!,
              key: const Key('clinical_note_error_label'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.destructive),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            key: const Key('clinical_note_save_button'),
            label: isSaving ? 'Saving…' : 'Save clinical note',
            icon: const Icon(Icons.save_outlined, size: 18),
            isLoading: isSaving,
            onPressed: isSaving ? null : () => notifier.save(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReadOnlySection(label: 'Complaint', value: state.complaint),
        _ReadOnlySection(label: 'History', value: state.history),
        _ReadOnlySection(label: 'Examination', value: state.examination),
        _ReadOnlySection(label: 'Diagnosis', value: state.diagnosis),
        _ReadOnlySection(label: 'Plan', value: state.plan),
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
  const _ReadOnlySection({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final display = value.trim().isEmpty ? '—' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: SpacingTokens.xs),
          Text(display, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.foreground)),
        ],
      ),
    );
  }
}

class _ClinicalNoteField extends StatelessWidget {
  const _ClinicalNoteField({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.enabled,
    this.hintText,
    super.key,
  });

  final String label;
  final String? hintText;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: AppTextInput(
        label: label,
        hintText: hintText,
        controller: controller,
        enabled: enabled,
        minLines: 3,
        maxLines: 8,
        onChanged: onChanged,
      ),
    );
  }
}
