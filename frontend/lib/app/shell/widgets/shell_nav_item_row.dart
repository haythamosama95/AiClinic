import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_badge.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_metrics.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shadow_tokens.dart';

/// Shared nav row with icon, label, optional badge/chevron, and hover pill.
///
/// The icon sits in a fixed-width slot at a constant horizontal offset so it
/// does not shift while the sidebar collapses or expands.
class ShellNavItemRow extends StatefulWidget {
  const ShellNavItemRow({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.badgeCount,
    this.badgeTone,
    this.trailing,
    this.hovered,
    this.enablePointerEvents = true,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final int? badgeCount;
  final ShellNavBadgeTone? badgeTone;
  final Widget? trailing;

  /// When [enablePointerEvents] is false, drives the hover pill from a parent [MouseRegion].
  final bool? hovered;

  /// When false, renders visuals only; pointer handling is delegated to a parent widget.
  final bool enablePointerEvents;

  @override
  State<ShellNavItemRow> createState() => _ShellNavItemRowState();
}

class _ShellNavItemRowState extends State<ShellNavItemRow> {
  var _isHovered = false;

  String _semanticsLabel() {
    final count = widget.badgeCount;
    if (count != null && count > 0 && widget.badgeTone != null) {
      return '${widget.label}, $count';
    }
    return widget.label;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final isHovered = widget.enablePointerEvents ? _isHovered : (widget.hovered ?? false);
    final isHighlighted = widget.isSelected || isHovered;
    final collapseT = ShellNavMetrics.maybeOf(context)?.collapseT ?? 0;
    final labelOpacity = (1 - collapseT).clamp(0.0, 1.0);
    final iconColor = widget.isSelected ? colors.foreground : colors.mutedForeground;
    final showBadgeDot =
        collapseT > 0.5 && widget.badgeCount != null && widget.badgeCount! > 0 && widget.badgeTone != null;

    final row = SizedBox(
      height: ShellTokens.itemHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: isHighlighted ? 1 : 0,
              duration: ShellTokens.hoverDuration,
              curve: Curves.easeOut,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(ShellTokens.itemRadius),
                  boxShadow: ShadowTokens.shadowSm,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ShellTokens.itemHorizontalPadding),
            child: Row(
              children: [
                SizedBox(
                  width: ShellTokens.itemIconSize,
                  height: ShellTokens.itemIconSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Icon(widget.icon, size: ShellTokens.itemIconSize, color: iconColor),
                      if (showBadgeDot)
                        Positioned(
                          top: -1,
                          right: -1,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.accent, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (collapseT < 1) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Opacity(
                      opacity: labelOpacity,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: iconColor,
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
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (!widget.enablePointerEvents) {
      return row;
    }

    final semanticsLabel = _semanticsLabel();

    return Semantics(
      button: true,
      label: semanticsLabel,
      selected: widget.isSelected,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: widget.onTap, behavior: HitTestBehavior.opaque, child: row),
      ),
    );
  }
}
