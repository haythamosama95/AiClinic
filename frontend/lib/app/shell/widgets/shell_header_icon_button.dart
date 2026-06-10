import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Circular icon control for shell header actions (notifications, settings, …).
class ShellHeaderIconButton extends StatefulWidget {
  const ShellHeaderIconButton({required this.icon, required this.tooltip, super.key});

  final IconData icon;
  final String tooltip;

  @override
  State<ShellHeaderIconButton> createState() => _ShellHeaderIconButtonState();
}

class _ShellHeaderIconButtonState extends State<ShellHeaderIconButton> {
  var _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: _isHovered ? colors.accent : colors.muted,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {},
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: ShellTokens.headerIconButtonSize,
              height: ShellTokens.headerIconButtonSize,
              child: Icon(widget.icon, size: 20, color: colors.foreground),
            ),
          ),
        ),
      ),
    );
  }
}
