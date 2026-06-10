import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Searchable option picker for bootstrap currency and timezone fields.
class SetupSearchableField extends StatelessWidget {
  const SetupSearchableField({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.validator,
    this.enabled = true,
    super.key,
  });

  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? hintText;
  final String? Function(String?)? validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final items = {for (final option in options) option: option};

    return AppAutocomplete<String>(
      label: label,
      items: items,
      value: value,
      hintText: hintText,
      enabled: enabled,
      onChanged: onChanged,
      validator: validator == null ? null : (selected) => validator!(selected),
    );
  }
}
