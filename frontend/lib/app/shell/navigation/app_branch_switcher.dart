import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/navigation/shell_nav_model.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Branch scope switcher for the top bar (`04-components` C9).
class AppBranchSwitcher extends StatelessWidget {
  const AppBranchSwitcher({
    required this.branches,
    required this.currentBranchId,
    required this.onBranchChange,
    super.key,
  });

  final List<ShellBranch> branches;
  final String? currentBranchId;
  final ValueChanged<String> onBranchChange;

  @override
  Widget build(BuildContext context) {
    if (branches.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = context.appColors;
    final current = branches.firstWhere((b) => b.id == currentBranchId, orElse: () => branches.first);

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceRaised),
        surfaceTintColor: WidgetStatePropertyAll(colors.surfaceRaised),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: colors.borderDefault),
          ),
        ),
      ),
      builder: (context, controller, child) {
        return InkWell(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 192),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceDefault,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.borderDefault),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.business_outlined, size: 16, color: colors.iconDefault),
                const SizedBox(width: AppSpacing.space2),
                Flexible(
                  child: Text(
                    current.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                Icon(Icons.expand_more, size: 16, color: colors.iconMuted),
              ],
            ),
          ),
        );
      },
      menuChildren: [
        if (current.org != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space3,
              AppSpacing.space2,
              AppSpacing.space3,
              AppSpacing.space1,
            ),
            child: Text(current.org!, style: AppTypography.overline(context)),
          ),
        for (final branch in branches)
          MenuItemButton(
            onPressed: branch.id == currentBranchId ? null : () => onBranchChange(branch.id),
            child: Row(
              children: [
                Expanded(child: Text(branch.name, overflow: TextOverflow.ellipsis)),
                if (branch.id == currentBranchId) Icon(Icons.check, size: 16, color: colors.textLink),
              ],
            ),
          ),
      ],
    );
  }
}
