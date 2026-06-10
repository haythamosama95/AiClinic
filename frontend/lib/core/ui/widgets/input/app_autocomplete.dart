import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'app_field_size.dart';

/// Application autocomplete with generic value typing.
class AppAutocomplete<T> extends StatelessWidget {
  const AppAutocomplete({
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.format,
    this.hintText,
    this.description,
    this.validator,
    this.enabled = true,
    this.size = AppFieldSize.md,
    super.key,
  });

  final String label;
  final Map<String, T> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String Function(T value)? format;
  final String? hintText;
  final String? description;
  final String? Function(T?)? validator;
  final bool enabled;
  final AppFieldSize size;

  String _labelFor(T item) {
    if (format != null) {
      return format!(item);
    }
    return items.entries
        .firstWhere((entry) => entry.value == item, orElse: () => throw StateError('No label for value: $item'))
        .key;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initialText = value == null ? null : TextEditingValue(text: _labelFor(value as T));

    return FAutocomplete<T>(
      items: items,
      control: FAutocompleteControl.managed(
        initial: initialText,
        onChange: (textValue) {
          final parsed = items[textValue.text];
          if (parsed != value) {
            onChanged?.call(parsed);
          }
        },
      ),
      size: size.forui,
      label: Text(label, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      hint: hintText,
      enabled: enabled,
      validator: validator,
      onItemPress: onChanged,
      autovalidateMode: validator != null ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
    );
  }
}
