import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'app_field_size.dart';

/// Selection mode for [AppSelectGroup] and [AppSelectTileGroup].
enum AppSelectGroupMode { radio, checkbox }

/// A labeled option for select groups.
class AppSelectOption<T> {
  const AppSelectOption({required this.value, required this.label, this.description});

  final T value;
  final String label;
  final String? description;
}

/// Application checkbox wrapping [FCheckbox].
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;
  final String? description;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FCheckbox(
      value: value,
      onChange: enabled ? onChanged : null,
      enabled: enabled,
      label: label == null ? null : Text(label!, style: theme.textTheme.bodyMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
    );
  }
}

/// Application radio wrapping [FRadio].
class AppRadio extends StatelessWidget {
  const AppRadio({
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;
  final String? description;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FRadio(
      value: value,
      onChange: enabled ? onChanged : null,
      enabled: enabled,
      label: label == null ? null : Text(label!, style: theme.textTheme.bodyMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
    );
  }
}

/// Application switch wrapping [FSwitch].
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;
  final String? description;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FSwitch(
      value: value,
      onChange: enabled ? onChanged : null,
      enabled: enabled,
      label: label == null ? null : Text(label!, style: theme.textTheme.bodyMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
    );
  }
}

/// Application single select wrapping [FSelect].
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.hintText,
    this.description,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.validator,
    super.key,
  });

  final String label;
  final Map<String, T> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? hintText;
  final String? description;
  final bool enabled;
  final AppFieldSize size;
  final String? Function(T?)? validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FSelect<T>(
      items: items,
      control: FSelectControl.lifted(value: value, onChange: onChanged ?? (_) {}),
      size: size.forui,
      label: Text(label, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      hint: hintText,
      enabled: enabled,
      validator: validator == null ? (_) => null : (v) => validator!(v),
      autovalidateMode: validator != null ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
    );
  }
}

/// Application multi select wrapping [FMultiSelect].
class AppMultiSelect<T> extends StatelessWidget {
  const AppMultiSelect({
    required this.label,
    required this.items,
    this.values = const {},
    this.onChanged,
    this.hintText,
    this.description,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.validator,
    super.key,
  });

  final String label;
  final Map<String, T> items;
  final Set<T> values;
  final ValueChanged<Set<T>>? onChanged;
  final String? hintText;
  final String? description;
  final bool enabled;
  final AppFieldSize size;
  final String? Function(Set<T>?)? validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FMultiSelect<T>(
      items: items,
      control: FMultiValueControl.lifted(value: values, onChange: onChanged ?? (_) {}),
      size: size.forui,
      label: Text(label, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      hint: hintText == null ? null : Text(hintText!),
      enabled: enabled,
      validator: validator ?? (_) => null,
      autovalidateMode: validator != null ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
    );
  }
}

/// Application select group wrapping [FSelectGroup].
class AppSelectGroup<T> extends StatelessWidget {
  const AppSelectGroup({
    required this.options,
    required this.values,
    required this.onChanged,
    this.label,
    this.description,
    this.mode = AppSelectGroupMode.radio,
    this.enabled = true,
    this.validator,
    super.key,
  });

  final List<AppSelectOption<T>> options;
  final Set<T> values;
  final ValueChanged<Set<T>> onChanged;
  final String? label;
  final String? description;
  final AppSelectGroupMode mode;
  final bool enabled;
  final String? Function(Set<T>?)? validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final control = FMultiValueControl<T>.lifted(value: values, onChange: onChanged);

    return FSelectGroup<T>(
      control: control,
      label: label == null ? null : Text(label!, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      enabled: enabled,
      validator: validator == null ? null : (v) => validator!(v),
      children: [
        for (final option in options)
          switch (mode) {
            AppSelectGroupMode.radio => FSelectGroupItemMixin.radio<T>(
              value: option.value,
              label: Text(option.label, style: theme.textTheme.bodyMedium),
              description: option.description == null
                  ? null
                  : Text(option.description!, style: theme.textTheme.bodySmall),
            ),
            AppSelectGroupMode.checkbox => FSelectGroupItemMixin.checkbox<T>(
              value: option.value,
              label: Text(option.label, style: theme.textTheme.bodyMedium),
              description: option.description == null
                  ? null
                  : Text(option.description!, style: theme.textTheme.bodySmall),
            ),
          },
      ],
    );
  }
}
