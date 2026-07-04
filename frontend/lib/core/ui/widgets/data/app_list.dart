import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Layout treatment for [AppList] items.
enum AppListVariant {
  /// Items separated by subtle horizontal dividers.
  divided,

  /// Items separated by vertical spacing without dividers.
  spaced,
}

/// Vertical list container for [AppListItem] children.
class AppList extends StatelessWidget {
  const AppList({
    required this.children,
    this.variant = AppListVariant.divided,
    this.semanticLabel,
    super.key,
  });

  final List<Widget> children;
  final AppListVariant variant;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final items = variant == AppListVariant.divided
        ? _buildDividedItems(colors)
        : _buildSpacedItems();

    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: Border.all(color: colors.borderDefault),
          borderRadius: AppRadii.lgAll,
        ),
        child: ClipRRect(
          borderRadius: AppRadii.lgAll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDividedItems(AppColors colors) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(Divider(
          height: AppSpacing.sPx,
          thickness: AppSpacing.sPx,
          color: colors.borderSubtle,
        ));
      }
      items.add(children[i]);
    }
    return items;
  }

  List<Widget> _buildSpacedItems() {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        items.add(const SizedBox(height: AppSpacing.s1));
      }
      items.add(children[i]);
    }
    return items;
  }
}

/// Single row in an [AppList] with leading, primary, secondary, and trailing
/// slots.
class AppListItem extends StatelessWidget {
  const AppListItem({
    required this.primary,
    this.leading,
    this.secondary,
    this.trailing,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final Widget? leading;
  final Widget primary;
  final Widget? secondary;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final interactive = onTap != null;

    Widget content = Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.s3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle(
                  style: typography.body.copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: primary,
                ),
                if (secondary != null) ...[
                  const SizedBox(height: AppSpacing.s0_5),
                  DefaultTextStyle(
                    style: typography.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: secondary!,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.s3),
            trailing!,
          ],
        ],
      ),
    );

    if (interactive) {
      content = AppPressable.builder(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        builder: (context, states, child) {
          final hovered = states.contains(WidgetState.hovered);
          final background = selected
              ? colors.surfaceSelected
              : hovered
              ? colors.surfaceHover
              : Colors.transparent;

          return AnimatedContainer(
            duration: AppDurations.instant,
            curve: AppEasings.standard,
            color: background,
            child: child,
          );
        },
        child: content,
      );
    } else if (selected) {
      content = ColoredBox(
        color: colors.surfaceSelected,
        child: content,
      );
    }

    return Semantics(
      selected: selected,
      button: interactive,
      child: content,
    );
  }
}
