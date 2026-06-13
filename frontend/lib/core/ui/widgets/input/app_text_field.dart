import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'app_field_size.dart';

const _fieldIconExtent = 32.0;

FTextFieldStyleDelta _inputFieldStyle(AppFieldSize size, {Color? fillColor}) => FTextFieldStyleDelta.delta(
  contentPadding: EdgeInsetsGeometryDelta.value(_inputContentPadding(size)),
  constraints: BoxConstraints(minHeight: _inputMinHeight(size)),
  color: fillColor == null ? null : FVariantsValueDelta.delta([FVariantValueDeltaOperation.base(fillColor)]),
);

EdgeInsets _inputContentPadding(AppFieldSize size) => switch (size) {
  AppFieldSize.sm => const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  AppFieldSize.md => const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
  AppFieldSize.lg => const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
};

double _inputMinHeight(AppFieldSize size) => switch (size) {
  AppFieldSize.sm => 38,
  AppFieldSize.md => 42,
  AppFieldSize.lg => 46,
};

Widget _centeredFieldIcon(Widget icon) => SizedBox(
  width: _fieldIconExtent,
  height: _fieldIconExtent,
  child: Center(child: icon),
);

Widget Function(BuildContext context, FTextFieldStyle style, Set<FTextFieldVariant> variants)? _prefixBuilder(
  Widget? icon,
) => icon == null
    ? null
    : (context, style, variants) => FTextField.prefixIconBuilder(context, style, variants, _centeredFieldIcon(icon));

Widget Function(BuildContext context, FTextFieldStyle style, Set<FTextFieldVariant> variants)? _suffixBuilder(
  Widget? icon,
) => icon == null
    ? null
    : (context, style, variants) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
        child: IconTheme(data: style.iconStyle.resolve(variants), child: _centeredFieldIcon(icon)),
      );

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
    this.onSubmit,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.inputFormatters,
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
  final ValueChanged<String>? onSubmit;
  final TextInputAction? textInputAction;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FTextFormField(
      control: controller != null
          ? FTextFieldControl.managed(
              controller: controller,
              onChange: onChanged == null ? null : (value) => onChanged!(value.text),
            )
          : FTextFieldControl.managed(onChange: onChanged == null ? null : (value) => onChanged!(value.text)),
      size: size.forui,
      label: Text(label, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      hint: hintText,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      enabled: enabled,
      onSubmit: onSubmit,
      validator: validator,
      inputFormatters: inputFormatters,
      prefixBuilder: _prefixBuilder(prefixIcon),
      suffixBuilder: _suffixBuilder(suffixIcon),
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
    this.minLines,
    this.maxLines = 1,
    this.expands = false,
    this.fillColor,
    this.textAlignVertical,
    this.onChanged,
    this.prefixIcon,
    this.suffixIcon,
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
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final Color? fillColor;
  final TextAlignVertical? textAlignVertical;
  final ValueChanged<String>? onChanged;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FTextField(
      control: controller != null
          ? FTextFieldControl.managed(
              controller: controller,
              onChange: onChanged == null ? null : (value) => onChanged!(value.text),
            )
          : FTextFieldControl.managed(onChange: onChanged == null ? null : (value) => onChanged!(value.text)),
      size: size.forui,
      style: _inputFieldStyle(size, fillColor: fillColor),
      label: label == null ? null : Text(label!, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      hint: hintText,
      obscureText: obscureText,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      expands: expands,
      textAlignVertical: textAlignVertical,
      enabled: enabled,
      prefixBuilder: _prefixBuilder(prefixIcon),
      suffixBuilder: _suffixBuilder(suffixIcon),
    );
  }
}
