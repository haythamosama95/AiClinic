import 'package:flutter/material.dart';

import 'package:ai_clinic/app/theme/app_colors.dart';
import 'package:ai_clinic/core/widgets/app_field_label.dart';
import 'package:ai_clinic/core/widgets/app_searchable_dropdown_field.dart';

/// Read-only display with a **Modify** action; editing uses [AppSearchableDropdownField].
class AppModifiableSearchableDropdownField extends StatefulWidget {
  const AppModifiableSearchableDropdownField({
    super.key,
    this.fieldKey,
    required this.label,
    required this.currentValue,
    required this.controller,
    required this.options,
    required this.filterOptions,
    this.infoTooltip,
    this.hint,
    this.enabled = true,
    this.validator,
    this.unsetMessage = 'This value has not been set before.',
  });

  final Key? fieldKey;
  final String label;
  final String? infoTooltip;
  final String? currentValue;
  final TextEditingController controller;
  final List<String> options;
  final List<String> Function(String query) filterOptions;
  final String? hint;
  final bool enabled;
  final String? Function(String?)? validator;
  final String unsetMessage;

  @override
  State<AppModifiableSearchableDropdownField> createState() => _AppModifiableSearchableDropdownFieldState();
}

class _AppModifiableSearchableDropdownFieldState extends State<AppModifiableSearchableDropdownField> {
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
      return AppSearchableDropdownField(
        fieldKey: widget.fieldKey,
        label: widget.label,
        infoTooltip: widget.infoTooltip,
        controller: widget.controller,
        enabled: widget.enabled,
        hint: widget.hint,
        options: widget.options,
        filterOptions: widget.filterOptions,
        validator: widget.validator,
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
