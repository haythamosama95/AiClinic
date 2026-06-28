import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// S/O/A/P fields with save and stale-conflict handling (V1-5 US2).
class SoapEditor extends ConsumerWidget {
  const SoapEditor({required this.visitId, required this.state, super.key});

  final String visitId;
  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!state.canEdit) {
      return _ReadOnlySoap(state: state);
    }
    if (state.soapEditMode == SoapEditMode.readOnly) {
      return _ReadOnlySoap(
        state: state,
        showEditButton: true,
        onEdit: () => ref.read(visitDocumentationProvider(visitId).notifier).enterSoapEditMode(),
      );
    }
    return _EditableSoap(visitId: visitId, state: state);
  }
}

class _EditableSoap extends ConsumerStatefulWidget {
  const _EditableSoap({required this.visitId, required this.state});

  final String visitId;
  final VisitDocumentationState state;

  @override
  ConsumerState<_EditableSoap> createState() => _EditableSoapState();
}

class _EditableSoapState extends ConsumerState<_EditableSoap> {
  late final TextEditingController _subjective;
  late final TextEditingController _objective;
  late final TextEditingController _assessment;
  late final TextEditingController _plan;

  @override
  void initState() {
    super.initState();
    _subjective = TextEditingController(text: widget.state.subjective);
    _objective = TextEditingController(text: widget.state.objective);
    _assessment = TextEditingController(text: widget.state.assessment);
    _plan = TextEditingController(text: widget.state.plan);
  }

  @override
  void didUpdateWidget(covariant _EditableSoap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.saveStatus == SoapSaveStatus.stale && widget.state.saveStatus != SoapSaveStatus.stale) {
      _subjective.text = widget.state.subjective;
      _objective.text = widget.state.objective;
      _assessment.text = widget.state.assessment;
      _plan.text = widget.state.plan;
    }
  }

  @override
  void dispose() {
    _subjective.dispose();
    _objective.dispose();
    _assessment.dispose();
    _plan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final isSaving = state.saveStatus == SoapSaveStatus.saving;
    final colors = context.semanticColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.saveStatus == SoapSaveStatus.stale) ...[
          AppAlert(
            key: const Key('soap_stale_banner'),
            title: state.errorMessage ?? 'This visit note was updated elsewhere. Reload and try again.',
            variant: AppAlertVariant.destructive,
            icon: const Icon(Icons.warning_amber_outlined),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const Key('soap_reload_button'),
              label: 'Reload',
              variant: AppButtonVariant.outline,
              onPressed: isSaving ? null : () => notifier.reloadAfterStale(),
            ),
          ),
          const SizedBox(height: SpacingTokens.md),
        ],
        _SoapField(
          key: const Key('soap_subjective'),
          label: 'Subjective',
          hintText: 'Patient-reported symptoms, history, and concerns',
          controller: _subjective,
          enabled: !isSaving,
          onChanged: notifier.updateSubjective,
        ),
        _SoapField(
          key: const Key('soap_objective'),
          label: 'Objective',
          hintText: 'Exam findings, vitals, and measurable observations',
          controller: _objective,
          enabled: !isSaving,
          onChanged: notifier.updateObjective,
        ),
        _SoapField(
          key: const Key('soap_assessment'),
          label: 'Assessment',
          hintText: 'Clinical impression and differential diagnosis',
          controller: _assessment,
          enabled: !isSaving,
          onChanged: notifier.updateAssessment,
        ),
        _SoapField(
          key: const Key('soap_plan'),
          label: 'Plan',
          hintText: 'Treatment plan, follow-up, and patient instructions',
          controller: _plan,
          enabled: !isSaving,
          onChanged: notifier.updatePlan,
        ),
        if (state.saveStatus == SoapSaveStatus.saved)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: Text(
              'Saved',
              key: const Key('soap_saved_label'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w600),
            ),
          ),
        if (state.saveStatus == SoapSaveStatus.error && state.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: Text(
              state.errorMessage!,
              key: const Key('soap_error_label'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.destructive),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            key: const Key('soap_save_button'),
            label: isSaving ? 'Saving…' : 'Save SOAP',
            icon: const Icon(Icons.save_outlined, size: 18),
            isLoading: isSaving,
            onPressed: isSaving ? null : () => notifier.save(),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlySoap extends StatelessWidget {
  const _ReadOnlySoap({required this.state, this.showEditButton = false, this.onEdit});

  final VisitDocumentationState state;
  final bool showEditButton;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReadOnlySection(label: 'Subjective', value: state.subjective),
        _ReadOnlySection(label: 'Objective', value: state.objective),
        _ReadOnlySection(label: 'Assessment', value: state.assessment),
        _ReadOnlySection(label: 'Plan', value: state.plan),
        if (showEditButton && onEdit != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const Key('soap_edit_button'),
              label: 'Edit SOAP',
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

class _SoapField extends StatelessWidget {
  const _SoapField({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.onChanged,
    required this.enabled,
    super.key,
  });

  final String label;
  final String hintText;
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
