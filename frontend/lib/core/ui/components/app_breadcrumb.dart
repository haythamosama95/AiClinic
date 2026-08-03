import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Single breadcrumb segment (web `BreadcrumbItem`).
class AppBreadcrumbItem {
  const AppBreadcrumbItem({required this.label, this.href, this.onTap});

  final String label;
  final String? href;
  final VoidCallback? onTap;
}

/// Hierarchical wayfinding trail (web `Breadcrumb`).
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({required this.items, super.key});

  static const _smBreakpoint = 640.0;

  final List<AppBreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: 'Breadcrumb',
      container: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < _smBreakpoint;

          return Row(
            children: [
              for (var index = 0; index < items.length; index++)
                if (!_shouldHideSegment(index: index, itemCount: items.length, isCompact: isCompact))
                  Flexible(
                    fit: FlexFit.loose,
                    child: _BreadcrumbSegment(
                      item: items[index],
                      index: index,
                      itemCount: items.length,
                      isCompact: isCompact,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  static bool _shouldHideSegment({required int index, required int itemCount, required bool isCompact}) {
    if (itemCount <= 3 || !isCompact) {
      return false;
    }
    final isMiddle = index > 0 && index < itemCount - 1;
    return isMiddle && (index == 1 || index == itemCount - 2);
  }
}

class _BreadcrumbSegment extends StatefulWidget {
  const _BreadcrumbSegment({required this.item, required this.index, required this.itemCount, required this.isCompact});

  final AppBreadcrumbItem item;
  final int index;
  final int itemCount;
  final bool isCompact;

  @override
  State<_BreadcrumbSegment> createState() => _BreadcrumbSegmentState();
}

class _BreadcrumbSegmentState extends State<_BreadcrumbSegment> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final index = widget.index;
    final itemCount = widget.itemCount;
    final item = widget.item;
    final isLast = index == itemCount - 1;

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final separatorIcon = isRtl ? Icons.chevron_left : Icons.chevron_right;

    final bodyStyle = AppTypography.bodySm(context);
    final label = Text(
      item.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: isLast
          ? bodyStyle.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w500)
          : bodyStyle.copyWith(color: _hovered ? colors.textLink : colors.textSecondary),
    );

    Widget labelWidget;
    if (isLast) {
      labelWidget = Semantics(
        label: item.label,
        hint: 'Current page',
        child: ExcludeSemantics(child: label),
      );
    } else if (item.href != null || item.onTap != null) {
      labelWidget = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(onTap: item.onTap, borderRadius: BorderRadius.circular(AppRadius.sm), child: label),
        ),
      );
    } else {
      labelWidget = label;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (index > 0) ...[
          Icon(separatorIcon, size: 14, color: colors.iconMuted),
          const SizedBox(width: AppSpacing.space1),
        ],
        if (index == 1 && itemCount > 3 && !widget.isCompact) ...[
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space1),
              child: Text('…', style: bodyStyle.copyWith(color: colors.textTertiary)),
            ),
          ),
        ],
        Flexible(child: labelWidget),
      ],
    );
  }
}
