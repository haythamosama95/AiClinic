import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Single segment in [AppBreadcrumb].
@immutable
class BreadcrumbItem {
  const BreadcrumbItem({
    required this.label,
    this.href,
    this.onTap,
  });

  final String label;
  final String? href;
  final VoidCallback? onTap;
}

/// Horizontal breadcrumb trail with mobile collapse for long paths.
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({
    super.key,
    required this.items,
  });

  final List<BreadcrumbItem> items;

  static const double _collapseBreakpoint = 640;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: 'Breadcrumb',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _collapseBreakpoint;
          return _BreadcrumbList(items: items, compact: compact);
        },
      ),
    );
  }
}

class _BreadcrumbList extends StatelessWidget {
  const _BreadcrumbList({
    required this.items,
    required this.compact,
  });

  final List<BreadcrumbItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography.bodySm;

    return Directionality(
      textDirection: Directionality.of(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) _Separator(),
            if (_shouldHideMiddle(index)) const SizedBox.shrink() else ...[
              if (index == 1 && items.length > 3 && !compact)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s1),
                  child: Text(
                    '…',
                    style: typography.copyWith(color: context.colors.textTertiary),
                  ),
                ),
              _BreadcrumbSegment(
                item: items[index],
                isLast: index == items.length - 1,
              ),
            ],
          ],
        ],
      ),
    );
  }

  bool _shouldHideMiddle(int index) {
    if (items.length <= 3 || !compact) return false;
    return index > 0 && index < items.length - 1 && (index == 1 || index == items.length - 2);
  }
}

class _Separator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isRtl = context.isRtl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s1),
      child: Icon(
        Icons.chevron_right,
        size: 14,
        color: context.colors.iconMuted,
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      ),
    );
  }
}

class _BreadcrumbSegment extends StatefulWidget {
  const _BreadcrumbSegment({
    required this.item,
    required this.isLast,
  });

  final BreadcrumbItem item;
  final bool isLast;

  @override
  State<_BreadcrumbSegment> createState() => _BreadcrumbSegmentState();
}

class _BreadcrumbSegmentState extends State<_BreadcrumbSegment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography.bodySm;
    final item = widget.item;
    final interactive = !widget.isLast && (item.href != null || item.onTap != null);

    final style = widget.isLast
        ? typography.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          )
        : typography.copyWith(
            color: interactive && _hovered ? colors.textLink : colors.textSecondary,
          );

    final textLabel = Text(
      item.label,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    Widget segment = textLabel;

    if (interactive) {
      segment = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: item.onTap,
          child: Focus(
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s0_5),
                  decoration: focused
                      ? BoxDecoration(
                          borderRadius: AppRadius.smAll,
                          border: Border.all(color: colors.focusRing, width: 2),
                        )
                      : null,
                  child: textLabel,
                );
              },
            ),
          ),
        ),
      );
    }

    return Flexible(
      child: Semantics(
        link: interactive,
        selected: widget.isLast,
        label: item.label,
        child: segment,
      ),
    );
  }
}
