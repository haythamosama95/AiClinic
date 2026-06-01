import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/specialty_form_schema.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Dynamic specialty fields from org JSON schema (V1-5 US3).
class SpecialtyFormFields extends ConsumerWidget {
  const SpecialtyFormFields({required this.visitId, required this.state, super.key});

  final String visitId;
  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!state.specialtySchema.hasFields) {
      return const SizedBox.shrink();
    }

    if (!state.canEdit) {
      return _ReadOnlySpecialty(state: state);
    }

    return _EditableSpecialty(visitId: visitId, state: state);
  }
}

class _EditableSpecialty extends ConsumerWidget {
  const _EditableSpecialty({required this.visitId, required this.state});

  final String visitId;
  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    final isSaving = state.saveStatus == SoapSaveStatus.saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in state.specialtySchema.fields) ...[
          _SpecialtyField(
            field: field,
            value: state.specialtyFormJson[field.key],
            errorText: state.specialtyFieldErrors[field.key],
            enabled: !isSaving,
            onChanged: (value) => notifier.updateSpecialtyField(field.key, value),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ReadOnlySpecialty extends StatelessWidget {
  const _ReadOnlySpecialty({required this.state});

  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in state.specialtySchema.fields) ...[
          _ReadOnlySpecialtyRow(
            label: field.label,
            value: _formatReadOnlyValue(field, state.specialtyFormJson[field.key]),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  String _formatReadOnlyValue(SpecialtyFormFieldDef field, Object? value) {
    if (value == null) {
      return '—';
    }
    if (field.type == 'boolean') {
      final boolValue = value is bool ? value : value.toString() == 'true';
      return boolValue ? 'Yes' : 'No';
    }
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }
}

class _ReadOnlySpecialtyRow extends StatelessWidget {
  const _ReadOnlySpecialtyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }
}

class _SpecialtyField extends StatefulWidget {
  const _SpecialtyField({
    required this.field,
    required this.value,
    required this.errorText,
    required this.enabled,
    required this.onChanged,
  });

  final SpecialtyFormFieldDef field;
  final Object? value;
  final String? errorText;
  final bool enabled;
  final ValueChanged<Object?> onChanged;

  @override
  State<_SpecialtyField> createState() => _SpecialtyFieldState();
}

class _SpecialtyFieldState extends State<_SpecialtyField> {
  TextEditingController? _textController;

  @override
  void initState() {
    super.initState();
    _initTextController();
  }

  @override
  void didUpdateWidget(covariant _SpecialtyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _textController != null) {
      _textController!.text = widget.value?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _textController?.dispose();
    super.dispose();
  }

  void _initTextController() {
    if (widget.field.type == 'boolean' || widget.field.isSelect) {
      return;
    }
    _textController = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final fieldKey = Key('specialty_field_${field.key}');

    if (field.type == 'boolean') {
      final checked = widget.value is bool ? widget.value as bool : widget.value?.toString() == 'true';
      return CheckboxListTile(
        key: fieldKey,
        title: Text(field.label),
        value: checked,
        enabled: widget.enabled,
        onChanged: widget.enabled ? (next) => widget.onChanged(next ?? false) : null,
        subtitle: widget.errorText != null
            ? Text(widget.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error))
            : null,
      );
    }

    if (field.isSelect) {
      final selected = widget.value?.toString();
      return DropdownButtonFormField<String>(
        key: fieldKey,
        initialValue: field.enumValues.contains(selected) ? selected : null,
        decoration: InputDecoration(
          labelText: field.label,
          border: const OutlineInputBorder(),
          errorText: widget.errorText,
        ),
        items: [for (final option in field.enumValues) DropdownMenuItem(value: option, child: Text(option))],
        onChanged: widget.enabled ? widget.onChanged : null,
      );
    }

    final keyboardType = field.type == 'number' || field.type == 'integer'
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text;

    return TextField(
      key: fieldKey,
      enabled: widget.enabled,
      keyboardType: keyboardType,
      controller: _textController,
      onChanged: (text) {
        if (field.type == 'number' || field.type == 'integer') {
          widget.onChanged(text.trim().isEmpty ? null : text);
        } else {
          widget.onChanged(text);
        }
      },
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
        errorText: widget.errorText,
      ),
    );
  }
}
