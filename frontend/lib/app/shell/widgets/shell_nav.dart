import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_group.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_metrics.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_single_item.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Left sidebar navigation for the authenticated shell.
class ShellNav extends StatefulWidget {
  const ShellNav({
    required this.selectedItemId,
    required this.expandedGroupIds,
    required this.onItemSelected,
    required this.onGroupToggled,
    super.key,
  });

  final String selectedItemId;
  final Set<String> expandedGroupIds;
  final ValueChanged<String> onItemSelected;
  final ValueChanged<String> onGroupToggled;

  @override
  State<ShellNav> createState() => _ShellNavState();
}

class _ShellNavState extends State<ShellNav> with SingleTickerProviderStateMixin {
  late final AnimationController _collapseController;
  late final Animation<double> _collapseAnimation;

  @override
  void initState() {
    super.initState();
    _collapseController = AnimationController(duration: ShellTokens.collapseDuration, vsync: this);
    _collapseAnimation = CurvedAnimation(parent: _collapseController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _collapseController.dispose();
    super.dispose();
  }

  void _toggleCollapse() {
    if (_collapseController.isCompleted) {
      _collapseController.reverse();
    } else {
      _collapseController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _collapseAnimation,
      builder: (context, _) {
        final width = lerpDouble(ShellTokens.navWidth, ShellTokens.navCollapsedWidth, _collapseAnimation.value)!;
        final isCollapsed = _collapseAnimation.value >= 1;

        return SizedBox(
          width: width,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: ShellTokens.navWidth,
              maxWidth: ShellTokens.navWidth,
              child: ShellNavMetrics(
                collapseT: _collapseAnimation.value,
                child: SizedBox(
                  width: ShellTokens.navWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: ShellTokens.headerHeight),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            SpacingTokens.md,
                            SpacingTokens.sm,
                            SpacingTokens.md,
                            SpacingTokens.lg,
                          ),
                          children: [
                            for (final entry in ShellNavConfig.entries)
                              switch (entry) {
                                ShellNavSingle() => Padding(
                                  padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
                                  child: ShellNavSingleItem(
                                    item: entry,
                                    isSelected: widget.selectedItemId == entry.id,
                                    onSelected: widget.onItemSelected,
                                  ),
                                ),
                                ShellNavGroup() => Padding(
                                  padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
                                  child: ShellNavGroupWidget(
                                    group: entry,
                                    isExpanded: widget.expandedGroupIds.contains(entry.id),
                                    selectedItemId: widget.selectedItemId,
                                    onToggle: widget.onGroupToggled,
                                    onSelected: widget.onItemSelected,
                                  ),
                                ),
                              },
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SpacingTokens.md,
                          SpacingTokens.sm,
                          SpacingTokens.md,
                          SpacingTokens.xs,
                        ),
                        child: ShellNavSingleItem(
                          item: ShellNavConfig.themeShowcaseFooter,
                          isSelected: widget.selectedItemId == ShellNavConfig.themeShowcaseId,
                          onSelected: widget.onItemSelected,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SpacingTokens.md,
                          SpacingTokens.sm,
                          SpacingTokens.md,
                          SpacingTokens.lg,
                        ),
                        child: ShellNavItemRow(
                          label: isCollapsed ? 'Expand' : 'Collapse',
                          icon: isCollapsed ? Icons.chevron_right : Icons.chevron_left,
                          isSelected: false,
                          onTap: _toggleCollapse,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
