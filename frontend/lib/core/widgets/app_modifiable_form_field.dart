import 'package:flutter/material.dart';

import 'package:ai_clinic/app/theme/app_colors.dart';
import 'package:ai_clinic/core/widgets/app_field_label.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';

/// Read-only display with a **Modify** action; editing uses [AppFormField].
class AppModifiableFormField extends StatefulWidget {
  const AppModifiableFormField({
    super.key,
    required this.label,
    required this.currentValue,
    required this.controller,
    this.infoTooltip,
    this.hint,
    this.enabled = true,
    this.validator,
    this.keyboardType,
    this.unsetMessage = 'This value has not been set before.',
  });

  final String label;
  final String? infoTooltip;
  final String? currentValue;
  final TextEditingController controller;
  final String? hint;
  final bool enabled;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final String unsetMessage;

  @override
  State<AppModifiableFormField> createState() => _AppModifiableFormFieldState();
}

class _AppModifiableFormFieldState extends State<AppModifiableFormField> {
  bool _isEditing = false;

  String? get _displayValue {
    final trimmed = widget.currentValue?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _startEditing() {
    if (!widget.enabled) {
      return;
    }
    widget.controller.text = _displayValue ?? '';
    setState(() => _isEditing = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return AppFormField(
        label: widget.label,
        infoTooltip: widget.infoTooltip,
        controller: widget.controller,
        enabled: widget.enabled,
        hint: widget.hint,
        validator: widget.validator,
        keyboardType: widget.keyboardType,
      );
    }

    final theme = Theme.of(context);
    final display = _displayValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldLabel(label: widget.label, infoTooltip: widget.infoTooltip),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                display ?? widget.unsetMessage,
                style: display == null
                    ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                    : theme.textTheme.bodyLarge,
              ),
            ),
            TextButton(onPressed: widget.enabled ? _startEditing : null, child: const Text('Modify')),
          ],
        ),
      ],
    );
  }
}
