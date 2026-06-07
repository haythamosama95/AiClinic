import 'package:flutter/material.dart';

import 'package:ai_clinic/app/theme/app_colors.dart';
import 'package:ai_clinic/core/widgets/app_field_label.dart';

/// Labeled text field aligned with the shared input decoration theme.
class AppFormField extends StatelessWidget {
  const AppFormField({
    super.key,
    required this.label,
    this.infoTooltip,
    this.hint,
    this.controller,
    this.validator,
    this.obscureText = false,
    this.enabled = true,
    this.keyboardType,
    this.maxLength,
    this.maxLines,
    this.onChanged,
  });

  final String label;
  final String? infoTooltip;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool obscureText;
  final bool enabled;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int? maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldLabel(label: label, infoTooltip: infoTooltip),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: controller,
          validator: validator,
          obscureText: obscureText,
          enabled: enabled,
          keyboardType: keyboardType,
          maxLength: maxLength,
          maxLines: maxLines,
          onChanged: onChanged,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
