import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';

/// Pressable top-level or child nav item.
class ShellNavSingleItem extends StatelessWidget {
  const ShellNavSingleItem({required this.item, required this.isSelected, required this.onSelected, super.key});

  final ShellNavSingle item;
  final bool isSelected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ShellNavItemRow(
      label: item.label,
      icon: item.icon,
      isSelected: isSelected,
      badgeCount: item.badgeCount,
      badgeTone: item.badgeTone,
      onTap: () => onSelected(item.id),
    );
  }
}
