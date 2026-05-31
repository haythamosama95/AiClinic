import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    if (!state.isEditable) {
      return _ReadOnlySoap(
        state: state,
        caption: 'This visit is ${state.visit.status.label.toLowerCase()}; SOAP cannot be edited.',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.saveStatus == SoapSaveStatus.stale) ...[
          MaterialBanner(
            key: const Key('soap_stale_banner'),
            content: Text(state.errorMessage ?? 'This visit note was updated elsewhere. Reload and try again.'),
            leading: const Icon(Icons.warning_amber),
            actions: [
              TextButton(
                key: const Key('soap_reload_button'),
                onPressed: isSaving ? null : () => notifier.reloadAfterStale(),
                child: const Text('Reload'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        _SoapField(
          key: const Key('soap_subjective'),
          label: 'Subjective',
          controller: _subjective,
          enabled: !isSaving,
          onChanged: notifier.updateSubjective,
        ),
        _SoapField(
          key: const Key('soap_objective'),
          label: 'Objective',
          controller: _objective,
          enabled: !isSaving,
          onChanged: notifier.updateObjective,
        ),
        _SoapField(
          key: const Key('soap_assessment'),
          label: 'Assessment',
          controller: _assessment,
          enabled: !isSaving,
          onChanged: notifier.updateAssessment,
        ),
        _SoapField(
          key: const Key('soap_plan'),
          label: 'Plan',
          controller: _plan,
          enabled: !isSaving,
          onChanged: notifier.updatePlan,
        ),
        const SizedBox(height: 12),
        if (state.saveStatus == SoapSaveStatus.saved)
          Text(
            'Saved',
            key: const Key('soap_saved_label'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        if (state.saveStatus == SoapSaveStatus.error && state.errorMessage != null)
          Text(
            state.errorMessage!,
            key: const Key('soap_error_label'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('soap_save_button'),
            onPressed: isSaving ? null : () => notifier.save(),
            icon: isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(isSaving ? 'Saving…' : 'Save SOAP'),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlySoap extends StatelessWidget {
  const _ReadOnlySoap({required this.state, this.caption});

  final VisitDocumentationState state;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption != null) ...[
          Text(caption!, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
        ],
        _ReadOnlySection(label: 'Subjective', value: state.subjective),
        _ReadOnlySection(label: 'Objective', value: state.objective),
        _ReadOnlySection(label: 'Assessment', value: state.assessment),
        _ReadOnlySection(label: 'Plan', value: state.plan),
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
    final display = value.trim().isEmpty ? '—' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(display),
        ],
      ),
    );
  }
}

class _SoapField extends StatelessWidget {
  const _SoapField({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.enabled,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
        minLines: 2,
        maxLines: 6,
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
