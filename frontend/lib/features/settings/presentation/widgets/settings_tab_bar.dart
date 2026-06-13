import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/settings/presentation/models/settings_tab.dart';

/// Horizontal, scrollable tab header for the settings page.
class SettingsTabBar extends StatelessWidget {
  const SettingsTabBar({required this.tabs, required this.selectedTabId, required this.onTabSelected, super.key});

  final List<SettingsTabDefinition> tabs;
  final String selectedTabId;
  final ValueChanged<String> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: SpacingTokens.lg),
              _SettingsTabItem(
                tab: tabs[i],
                isSelected: tabs[i].id == selectedTabId,
                onTap: () => onTabSelected(tabs[i].id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsTabItem extends StatefulWidget {
  const _SettingsTabItem({required this.tab, required this.isSelected, required this.onTap});

  final SettingsTabDefinition tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_SettingsTabItem> createState() => _SettingsTabItemState();
}

class _SettingsTabItemState extends State<_SettingsTabItem> {
  var _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final isActive = widget.isSelected;
    final contentColor = isActive ? colors.primary : (_isHovered ? colors.foreground : colors.mutedForeground);

    return Semantics(
      button: true,
      selected: isActive,
      label: widget.tab.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.md),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.tab.icon, size: 18, color: contentColor),
                        const SizedBox(width: SpacingTokens.sm),
                        Text(
                          widget.tab.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: contentColor,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    height: 3,
                    color: isActive ? colors.primary : Colors.transparent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
