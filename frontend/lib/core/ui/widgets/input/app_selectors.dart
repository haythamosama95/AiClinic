import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

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
    this.autovalidateMode,
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
  final AutovalidateMode? autovalidateMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedAutovalidateMode =
        autovalidateMode ?? (validator != null ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled);

    return FSelect<T>(
      items: items,
      control: FSelectControl.lifted(value: value, onChange: onChanged ?? (_) {}),
      size: size.forui,
      label: Text(label, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      hint: hintText,
      enabled: enabled,
      validator: validator == null ? (_) => null : (v) => validator!(v),
      autovalidateMode: resolvedAutovalidateMode,
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
    this.autovalidateMode,
    this.control,
    this.contentGroupId,
    this.contentHideRegion,
    this.showPopoverCloseButton = false,
    super.key,
  });

  final String label;
  final Map<String, T> items;
  final Set<T> values;
  final ValueChanged<Set<T>>? onChanged;
  final FMultiValueControl<T>? control;
  final String? hintText;
  final String? description;
  final bool enabled;
  final AppFieldSize size;
  final String? Function(Set<T>?)? validator;
  final AutovalidateMode? autovalidateMode;
  final Object? contentGroupId;
  final FPopoverHideRegion? contentHideRegion;
  final bool showPopoverCloseButton;

  static FMultiSelectPopoverBuilder<T> _popoverWithCloseButton<T>() {
    return (context, _, popoverController, content) {
      final colors = context.semanticColors;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: popoverController.hide,
              icon: Icon(Icons.close, size: 18, color: colors.mutedForeground),
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(SpacingTokens.xs),
                minimumSize: const Size(28, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: 'Close',
            ),
          ),
          content,
        ],
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedAutovalidateMode =
        autovalidateMode ?? (validator != null ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled);

    return FMultiSelect<T>(
      items: items,
      control: control ?? FMultiValueControl.lifted(value: values, onChange: onChanged ?? (_) {}),
      size: size.forui,
      label: Text(label, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      hint: hintText == null ? null : Text(hintText!),
      enabled: enabled,
      validator: validator ?? (_) => null,
      autovalidateMode: resolvedAutovalidateMode,
      contentGroupId: contentGroupId,
      contentHideRegion: contentHideRegion ?? FPopoverHideRegion.excludeChild,
      popoverBuilder: showPopoverCloseButton ? _popoverWithCloseButton<T>() : FPopover.defaultPopoverBuilder,
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
