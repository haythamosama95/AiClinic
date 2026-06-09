import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../input/app_selectors.dart';

/// Semantic tile variants.
enum AppTileVariant { primary, destructive }

/// Data model for tiles inside [AppTileGroup].
class AppTileSpec {
  const AppTileSpec({
    required this.title,
    this.subtitle,
    this.details,
    this.prefix,
    this.suffix,
    this.onPressed,
    this.selected = false,
    this.enabled = true,
    this.variant = AppTileVariant.primary,
  });

  final String title;
  final String? subtitle;
  final String? details;
  final Widget? prefix;
  final Widget? suffix;
  final VoidCallback? onPressed;
  final bool selected;
  final bool enabled;
  final AppTileVariant variant;
}

/// Application list tile wrapping [FTile].
class AppTile extends StatelessWidget {
  const AppTile({
    required this.title,
    this.subtitle,
    this.details,
    this.prefix,
    this.suffix,
    this.onPressed,
    this.selected = false,
    this.enabled = true,
    this.variant = AppTileVariant.primary,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? details;
  final Widget? prefix;
  final Widget? suffix;
  final VoidCallback? onPressed;
  final bool selected;
  final bool enabled;
  final AppTileVariant variant;

  @override
  Widget build(BuildContext context) => _buildTile(
    context,
    AppTileSpec(
      title: title,
      subtitle: subtitle,
      details: details,
      prefix: prefix,
      suffix: suffix,
      onPressed: onPressed,
      selected: selected,
      enabled: enabled,
      variant: variant,
    ),
  );

  static FTile _buildTile(BuildContext context, AppTileSpec spec) {
    final theme = Theme.of(context);

    return FTile(
      variant: spec.variant == AppTileVariant.destructive ? FItemVariant.destructive : FItemVariant.primary,
      title: Text(spec.title, style: theme.textTheme.bodyMedium),
      subtitle: spec.subtitle == null ? null : Text(spec.subtitle!, style: theme.textTheme.bodySmall),
      details: spec.details == null ? null : Text(spec.details!, style: theme.textTheme.bodySmall),
      prefix: spec.prefix,
      suffix: spec.suffix,
      onPress: spec.enabled ? spec.onPressed : null,
      selected: spec.selected,
      enabled: spec.enabled,
    );
  }
}

/// Application tile group wrapping [FTileGroup].
class AppTileGroup extends StatelessWidget {
  const AppTileGroup({required this.tiles, this.label, this.description, super.key});

  final List<AppTileSpec> tiles;
  final String? label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FTileGroup(
      style: context.theme.tileGroupStyle,
      label: label == null ? null : Text(label!, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      children: [for (final tile in tiles) AppTile._buildTile(context, tile)],
    );
  }
}

/// Data model for items inside [AppItemGroup].
class AppItemSpec {
  const AppItemSpec({
    required this.title,
    this.subtitle,
    this.details,
    this.prefix,
    this.suffix,
    this.onPressed,
    this.selected = false,
    this.enabled = true,
    this.variant = AppTileVariant.primary,
  });

  final String title;
  final String? subtitle;
  final String? details;
  final Widget? prefix;
  final Widget? suffix;
  final VoidCallback? onPressed;
  final bool selected;
  final bool enabled;
  final AppTileVariant variant;
}

/// Application item wrapping [FItem] for dense desktop lists.
class AppItem extends StatelessWidget {
  const AppItem({
    required this.title,
    this.subtitle,
    this.details,
    this.prefix,
    this.suffix,
    this.onPressed,
    this.selected = false,
    this.enabled = true,
    this.variant = AppTileVariant.primary,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? details;
  final Widget? prefix;
  final Widget? suffix;
  final VoidCallback? onPressed;
  final bool selected;
  final bool enabled;
  final AppTileVariant variant;

  @override
  Widget build(BuildContext context) => _buildItem(
    context,
    AppItemSpec(
      title: title,
      subtitle: subtitle,
      details: details,
      prefix: prefix,
      suffix: suffix,
      onPressed: onPressed,
      selected: selected,
      enabled: enabled,
      variant: variant,
    ),
  );

  static FItem _buildItem(BuildContext context, AppItemSpec spec) {
    final theme = Theme.of(context);

    return FItem(
      variant: spec.variant == AppTileVariant.destructive ? FItemVariant.destructive : FItemVariant.primary,
      title: Text(spec.title, style: theme.textTheme.bodyMedium),
      subtitle: spec.subtitle == null ? null : Text(spec.subtitle!, style: theme.textTheme.bodySmall),
      details: spec.details == null ? null : Text(spec.details!, style: theme.textTheme.bodySmall),
      prefix: spec.prefix,
      suffix: spec.suffix,
      onPress: spec.enabled ? spec.onPressed : null,
      selected: spec.selected,
      enabled: spec.enabled,
    );
  }
}

/// Application item group wrapping [FItemGroup].
class AppItemGroup extends StatelessWidget {
  const AppItemGroup({required this.items, super.key});

  final List<AppItemSpec> items;

  @override
  Widget build(BuildContext context) {
    return FItemGroup(
      style: context.theme.itemGroupStyle,
      children: [for (final item in items) AppItem._buildItem(context, item)],
    );
  }
}

/// Application select menu tile wrapping [FSelectMenuTile].
class AppSelectMenuTile<T> extends StatelessWidget {
  const AppSelectMenuTile({
    required this.title,
    required this.items,
    required this.values,
    required this.onChanged,
    this.label,
    this.description,
    this.mode = AppSelectGroupMode.radio,
    this.enabled = true,
    super.key,
  });

  final String title;
  final Map<String, T> items;
  final Set<T> values;
  final ValueChanged<Set<T>> onChanged;
  final String? label;
  final String? description;
  final AppSelectGroupMode mode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (mode == AppSelectGroupMode.radio) {
      assert(values.length <= 1, 'AppSelectMenuTile radio mode expects at most one value, got ${values.length}.');
    }

    final control = switch (mode) {
      AppSelectGroupMode.radio => FMultiValueControl<T>.managedRadio(
        initial: values.isEmpty ? null : values.first,
        onChange: onChanged,
      ),
      AppSelectGroupMode.checkbox => FMultiValueControl<T>.lifted(value: values, onChange: onChanged),
    };

    return FSelectMenuTile<T>.fromMap(
      items,
      title: Text(title, style: theme.textTheme.bodyMedium),
      selectControl: control,
      label: label == null ? null : Text(label!, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      enabled: enabled,
    );
  }
}

/// Application select tile group wrapping [FSelectTileGroup].
class AppSelectTileGroup<T> extends StatelessWidget {
  const AppSelectTileGroup({
    required this.options,
    required this.values,
    required this.onChanged,
    this.label,
    this.description,
    this.mode = AppSelectGroupMode.radio,
    this.enabled = true,
    super.key,
  });

  final List<AppSelectOption<T>> options;
  final Set<T> values;
  final ValueChanged<Set<T>> onChanged;
  final String? label;
  final String? description;
  final AppSelectGroupMode mode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (mode == AppSelectGroupMode.radio) {
      assert(values.length <= 1, 'AppSelectTileGroup radio mode expects at most one value, got ${values.length}.');
    }

    final control = switch (mode) {
      AppSelectGroupMode.radio => FMultiValueControl<T>.managedRadio(
        initial: values.isEmpty ? null : values.first,
        onChange: onChanged,
      ),
      AppSelectGroupMode.checkbox => FMultiValueControl<T>.lifted(value: values, onChange: onChanged),
    };

    return FSelectTileGroup<T>.builder(
      control: control,
      count: options.length,
      label: label == null ? null : Text(label!, style: theme.textTheme.labelMedium),
      description: description == null ? null : Text(description!, style: theme.textTheme.bodySmall),
      enabled: enabled,
      tileBuilder: (context, index) {
        final option = options[index];
        return FSelectTile<T>.tile(
          title: Text(option.label, style: theme.textTheme.bodyMedium),
          subtitle: option.description == null ? null : Text(option.description!, style: theme.textTheme.bodySmall),
          value: option.value,
        );
      },
    );
  }
}
