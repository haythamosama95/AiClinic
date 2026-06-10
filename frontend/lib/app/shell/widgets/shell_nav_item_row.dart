import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_badge.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shadow_tokens.dart';

/// Shared nav row with icon, label, optional badge/chevron, and hover pill.
class ShellNavItemRow extends StatefulWidget {
  const ShellNavItemRow({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.badgeCount,
    this.badgeTone,
    this.trailing,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final int? badgeCount;
  final ShellNavBadgeTone? badgeTone;
  final Widget? trailing;

  @override
  State<ShellNavItemRow> createState() => _ShellNavItemRowState();
}

class _ShellNavItemRowState extends State<ShellNavItemRow> {
  var _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final isHighlighted = widget.isSelected || _isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: ShellTokens.hoverDuration,
          curve: Curves.easeOut,
          height: ShellTokens.itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: ShellTokens.itemHorizontalPadding),
          decoration: BoxDecoration(
            color: isHighlighted ? colors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(ShellTokens.itemRadius),
            boxShadow: isHighlighted ? ShadowTokens.shadowSm : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: ShellTokens.itemIconSize,
                color: widget.isSelected ? colors.foreground : colors.mutedForeground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: widget.isSelected ? colors.foreground : colors.mutedForeground,
                    fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (widget.badgeCount != null && widget.badgeTone != null) ...[
                const SizedBox(width: 8),
                ShellNavBadge(count: widget.badgeCount!, tone: widget.badgeTone!),
              ],
              if (widget.trailing != null) ...[const SizedBox(width: 4), widget.trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
