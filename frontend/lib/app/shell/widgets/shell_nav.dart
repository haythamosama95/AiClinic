import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_group.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_logo.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_single_item.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Left sidebar navigation for the authenticated shell.
class ShellNav extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      width: ShellTokens.navWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
            child: ShellNavLogo(),
          ),
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
                        isSelected: selectedItemId == entry.id,
                        onSelected: onItemSelected,
                      ),
                    ),
                    ShellNavGroup() => Padding(
                      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
                      child: ShellNavGroupWidget(
                        group: entry,
                        isExpanded: expandedGroupIds.contains(entry.id),
                        selectedItemId: selectedItemId,
                        onToggle: onGroupToggled,
                        onSelected: onItemSelected,
                      ),
                    ),
                  },
              ],
            ),
          ),
        ],
      ),
    );
  }
}
