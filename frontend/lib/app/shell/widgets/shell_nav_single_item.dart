import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_item_row.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';

/// Pressable top-level or child nav item.
class ShellNavSingleItem extends ConsumerWidget {
  const ShellNavSingleItem({required this.item, required this.isSelected, required this.onSelected, super.key});

  final ShellNavSingle item;
  final bool isSelected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeCount = item.id == ShellNavConfig.queueNavItemId
        ? ref.watch(appointmentQueueCheckedInCountProvider)
        : item.badgeCount;

    return ShellNavItemRow(
      label: item.label,
      icon: item.icon,
      isSelected: isSelected,
      badgeCount: badgeCount,
      badgeTone: item.badgeTone,
      onTap: () => onSelected(item.id),
    );
  }
}
