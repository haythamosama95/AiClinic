import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/icons/app_icon_size.dart';
import 'package:ai_clinic/core/ui/theme/theme_context.dart';

/// Lucide icon wrapper with design-system sizing, color, and RTL mirroring.
class AppIcon extends StatelessWidget {
  /// Creates an icon using [size] (default [AppIconSize.md]) unless [dimension]
  /// overrides it.
  const AppIcon({
    required this.icon,
    this.size = AppIconSize.md,
    this.dimension,
    this.color,
    this.semanticLabel,
    this.mirrorInRtl = false,
    super.key,
  });

  final IconData icon;
  final AppIconSize size;
  final double? dimension;
  final Color? color;
  final String? semanticLabel;
  final bool mirrorInRtl;

  double get _resolvedSize => dimension ?? size.value;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? context.colors.iconDefault;

    Widget iconWidget = Icon(
      icon,
      size: _resolvedSize,
      color: resolvedColor,
      semanticLabel: semanticLabel,
    );

    if (mirrorInRtl && Directionality.of(context) == TextDirection.rtl) {
      iconWidget = Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(math.pi),
        child: iconWidget,
      );
    }

    return iconWidget;
  }
}
