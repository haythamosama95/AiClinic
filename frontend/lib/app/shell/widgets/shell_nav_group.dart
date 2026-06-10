import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_metrics.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_single_item.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_tree_connector.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Expandable nav group with tree connectors to child items.
class ShellNavGroupWidget extends StatefulWidget {
  const ShellNavGroupWidget({
    required this.group,
    required this.isExpanded,
    required this.selectedItemId,
    required this.onToggle,
    required this.onSelected,
    super.key,
  });

  final ShellNavGroup group;
  final bool isExpanded;
  final String selectedItemId;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onSelected;

  @override
  State<ShellNavGroupWidget> createState() => _ShellNavGroupWidgetState();
}

class _ShellNavGroupWidgetState extends State<ShellNavGroupWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _expandController;
  late final Animation<double> _expandAnimation;
  late final Animation<double> _chevronRotation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(duration: ShellTokens.expandDuration, vsync: this);
    _expandAnimation = CurvedAnimation(parent: _expandController, curve: Curves.easeInOut);
    _chevronRotation = Tween<double>(begin: 0, end: 0.5).animate(_expandAnimation);
    if (widget.isExpanded) {
      _expandController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant ShellNavGroupWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded == oldWidget.isExpanded) return;

    if (widget.isExpanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final isGroupSelected = widget.group.children.any((child) => child.id == widget.selectedItemId);
    final collapseT = ShellNavMetrics.maybeOf(context)?.collapseT ?? 0;
    final isNavCollapsed = collapseT > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShellNavItemRow(
          label: widget.group.label,
          icon: widget.group.icon,
          isSelected: isGroupSelected && !widget.isExpanded,
          onTap: () => widget.onToggle(widget.group.id),
          trailing: isNavCollapsed
              ? null
              : RotationTransition(
                  turns: _chevronRotation,
                  child: Icon(Icons.keyboard_arrow_down, size: 20, color: colors.mutedForeground),
                ),
        ),
        if (isNavCollapsed)
          const SizedBox.shrink()
        else
          AnimatedBuilder(
            animation: _expandAnimation,
            builder: (context, child) {
              return ClipRect(
                child: Align(alignment: Alignment.topCenter, heightFactor: _expandAnimation.value, child: child),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(left: ShellTokens.itemHorizontalPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShellNavTreeConnector(childCount: widget.group.children.length),
                  Expanded(
                    child: Column(
                      children: [
                        for (final child in widget.group.children)
                          ShellNavSingleItem(
                            item: child,
                            isSelected: widget.selectedItemId == child.id,
                            onSelected: widget.onSelected,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
