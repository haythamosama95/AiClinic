import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// Application-owned icon button (`04-components` A2).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = AppIconButtonSize.md,
    super.key,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final AppIconButtonSize size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dimension = switch (size) {
      AppIconButtonSize.sm => 28.0,
      AppIconButtonSize.md => 32.0,
      AppIconButtonSize.lg => 40.0,
    };

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: icon,
        iconSize: size == AppIconButtonSize.lg ? 24 : 20,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: dimension, height: dimension),
        style: IconButton.styleFrom(
          foregroundColor: colors.iconDefault,
          hoverColor: colors.surfaceHover,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
    );
  }
}

enum AppIconButtonSize { sm, md, lg }
