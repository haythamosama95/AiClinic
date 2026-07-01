import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Semantic icon button variants.
enum AppIconButtonVariant { ghost, outline, muted }

/// Compact icon-only button for toolbars and secondary actions.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.variant = AppIconButtonVariant.ghost,
    this.size = 32,
    super.key,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final (background, border, foreground) = switch (variant) {
      AppIconButtonVariant.ghost => (Colors.transparent, Colors.transparent, colors.foreground),
      AppIconButtonVariant.outline => (colors.background, colors.border, colors.foreground),
      AppIconButtonVariant.muted => (colors.muted, colors.border, colors.mutedForeground),
    };

    var style = IconButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      surfaceTintColor: variant == AppIconButtonVariant.ghost ? Colors.transparent : null,
      side: border == Colors.transparent ? null : BorderSide(color: border),
      padding: const EdgeInsets.all(SpacingTokens.xs),
      minimumSize: Size(size, size),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    if (variant == AppIconButtonVariant.ghost) {
      style = style.copyWith(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return null;
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return foreground.withValues(alpha: 0.08);
          }
          return Colors.transparent;
        }),
      );
    }

    return IconButton(tooltip: tooltip, onPressed: onPressed, icon: icon, style: style);
  }
}
