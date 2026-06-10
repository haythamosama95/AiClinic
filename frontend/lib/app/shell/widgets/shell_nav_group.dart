import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_single_item.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_tree_connector.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Expandable nav group with tree connectors to child items.
class ShellNavGroupWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final isGroupSelected = group.children.any((child) => child.id == selectedItemId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShellNavItemRow(
          label: group.label,
          icon: group.icon,
          isSelected: isGroupSelected && !isExpanded,
          onTap: () => onToggle(group.id),
          trailing: AnimatedRotation(
            turns: isExpanded ? 0.5 : 0,
            duration: ShellTokens.hoverDuration,
            curve: Curves.easeOut,
            child: Icon(Icons.keyboard_arrow_down, size: 20, color: colors.mutedForeground),
          ),
        ),
        AnimatedSize(
          duration: ShellTokens.hoverDuration,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: isExpanded
              ? Padding(
                  padding: const EdgeInsets.only(left: ShellTokens.itemHorizontalPadding),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShellNavTreeConnector(childCount: group.children.length),
                      Expanded(
                        child: Column(
                          children: [
                            for (final child in group.children)
                              ShellNavSingleItem(
                                item: child,
                                isSelected: selectedItemId == child.id,
                                onSelected: onSelected,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
