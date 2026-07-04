import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/navigation/app_menu.dart';

/// One segment in an [AppBreadcrumb] trail.
class AppBreadcrumbItem {
  const AppBreadcrumbItem({
    required this.label,
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;
}

/// Hierarchical wayfinding trail with overflow collapse into [AppMenu].
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({
    required this.items,
    this.maxVisible = 3,
    super.key,
  });

  final List<AppBreadcrumbItem> items;

  /// Maximum crumbs shown before middle segments collapse into an overflow menu.
  final int maxVisible;

  static const double _separatorIconSize = 14;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final typography = context.typography;
    final linkStyle = typography.bodySm.copyWith(color: colors.textSecondary);
    final currentStyle = typography.bodySm.copyWith(
      fontWeight: FontWeight.w500,
      color: colors.textPrimary,
    );

    final segments = _resolveSegments(items, maxVisible);

    return Semantics(
      label: 'Breadcrumb',
      container: true,
      child: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) _Separator(color: colors.iconMuted),
                _Segment(
                  segment: segments[i],
                  linkStyle: linkStyle,
                  currentStyle: currentStyle,
                  colors: colors,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

sealed class _BreadcrumbSegment {
  const _BreadcrumbSegment();
}

final class _BreadcrumbLinkSegment extends _BreadcrumbSegment {
  const _BreadcrumbLinkSegment(this.item, {required this.isCurrent});

  final AppBreadcrumbItem item;
  final bool isCurrent;
}

final class _BreadcrumbOverflowSegment extends _BreadcrumbSegment {
  const _BreadcrumbOverflowSegment(this.hiddenItems);

  final List<AppBreadcrumbItem> hiddenItems;
}

List<_BreadcrumbSegment> _resolveSegments(
  List<AppBreadcrumbItem> items,
  int maxVisible,
) {
  if (items.length <= maxVisible) {
    return [
      for (var i = 0; i < items.length; i++)
        _BreadcrumbLinkSegment(items[i], isCurrent: i == items.length - 1),
    ];
  }

  final hidden = items.sublist(1, items.length - 1);
  return [
    _BreadcrumbLinkSegment(items.first, isCurrent: false),
    _BreadcrumbOverflowSegment(hidden),
    _BreadcrumbLinkSegment(items.last, isCurrent: true),
  ];
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final icon = AppIcon(
      icon: LucideIcons.chevronRight,
      dimension: AppBreadcrumb._separatorIconSize,
      color: color,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s1),
      child: isRtl ? Transform.flip(flipX: true, child: icon) : icon,
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.linkStyle,
    required this.currentStyle,
    required this.colors,
  });

  final _BreadcrumbSegment segment;
  final TextStyle linkStyle;
  final TextStyle currentStyle;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return switch (segment) {
      _BreadcrumbLinkSegment(:final item, :final isCurrent) => _LinkCrumb(
        item: item,
        isCurrent: isCurrent,
        linkStyle: linkStyle,
        currentStyle: currentStyle,
        colors: colors,
      ),
      _BreadcrumbOverflowSegment(:final hiddenItems) => _OverflowCrumb(
        hiddenItems: hiddenItems,
        linkStyle: linkStyle,
        colors: colors,
      ),
    };
  }
}

class _LinkCrumb extends StatelessWidget {
  const _LinkCrumb({
    required this.item,
    required this.isCurrent,
    required this.linkStyle,
    required this.currentStyle,
    required this.colors,
  });

  final AppBreadcrumbItem item;
  final bool isCurrent;
  final TextStyle linkStyle;
  final TextStyle currentStyle;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final text = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Text(
        item.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (isCurrent) {
      return Semantics(
        selected: true,
        child: DefaultTextStyle(style: currentStyle, child: text),
      );
    }

    if (item.onTap == null) {
      return DefaultTextStyle(style: linkStyle, child: text);
    }

    return AppPressable.builder(
      onTap: item.onTap,
      semanticLabel: item.label,
      borderRadius: AppRadii.smAll,
      builder: (context, states, _) {
        final hovered = states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        final style = linkStyle.copyWith(
          color: hovered ? colors.textLink : colors.textSecondary,
        );
        return DefaultTextStyle(style: style, child: text);
      },
    );
  }
}

class _OverflowCrumb extends StatelessWidget {
  const _OverflowCrumb({
    required this.hiddenItems,
    required this.linkStyle,
    required this.colors,
  });

  final List<AppBreadcrumbItem> hiddenItems;
  final TextStyle linkStyle;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return AppMenu(
      align: AppMenuAlign.start,
      entries: [
        for (final item in hiddenItems)
          AppMenuItemEntry(
            AppMenuItem(
              id: item.label,
              label: item.label,
              onSelected: item.onTap,
              disabled: item.onTap == null,
            ),
          ),
      ],
      trigger: (context, show, hide, toggle) {
        return AppPressable(
          onTap: show,
          semanticLabel: 'Show hidden breadcrumb items',
          borderRadius: AppRadii.smAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  icon: LucideIcons.moreHorizontal,
                  dimension: AppIconSize.sm.value,
                  color: colors.textTertiary,
                ),
                Text(
                  '…',
                  style: linkStyle.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
