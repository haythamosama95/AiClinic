import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'app_field_size.dart';

/// Application text form field wrapping [FTextFormField].
class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.label,
    this.hintText,
    this.controller,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.description,
    this.maxLines = 1,
    this.onChanged,
    super.key,
  });

  final String label;
  final String? hintText;
  final String? description;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool enabled;
  final AppFieldSize size;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FTextFormField(
      control: controller != null
          ? FTextFieldControl.managed(controller: controller)
          : const FTextFieldControl.managed(),
      size: size.forui,
      label: Text(label, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      hint: hintText,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      validator: validator,
      onSubmit: onChanged,
      autovalidateMode: validator != null ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
    );
  }
}

/// Application text field wrapping [FTextField] for use outside [Form].
class AppTextInput extends StatelessWidget {
  const AppTextInput({
    this.label,
    this.hintText,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.description,
    this.maxLines = 1,
    this.onChanged,
    super.key,
  });

  final String? label;
  final String? hintText;
  final String? description;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool enabled;
  final AppFieldSize size;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FTextField(
      control: controller != null
          ? FTextFieldControl.managed(controller: controller)
          : const FTextFieldControl.managed(),
      size: size.forui,
      label: label == null ? null : Text(label!, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      hint: hintText,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      onSubmit: onChanged,
    );
  }
}
