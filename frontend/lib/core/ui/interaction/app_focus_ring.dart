import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/theme_context.dart';
import 'package:ai_clinic/core/ui/tokens/app_durations.dart';
import 'package:ai_clinic/core/ui/tokens/app_signal_tokens.dart';

/// Focus ring color variant.
enum AppFocusRingVariant {
  /// Teal ring for standard interactive elements.
  standard,

  /// Violet ring for AI-accented interactive elements.
  ai,
}

/// Always-visible focus ring drawn outside [child] bounds (CSS outline-offset).
class AppFocusRing extends StatelessWidget {
  const AppFocusRing({
    required this.visible,
    required this.child,
    this.variant = AppFocusRingVariant.standard,
    this.borderRadius,
    super.key,
  });

  /// Whether the focus ring is shown.
  final bool visible;

  /// Content enclosed by the ring.
  final Widget child;

  /// Ring color token variant.
  final AppFocusRingVariant variant;

  /// Corner radius of the child; expanded outward to follow the outline.
  final BorderRadius? borderRadius;

  static const double _ringWidth = AppSignal.thickness;
  static const double _ringOffset = AppSignal.thickness;
  static const double _outerInset = _ringOffset + _ringWidth;

  Color _ringColor(BuildContext context) {
    final colors = context.colors;
    return switch (variant) {
      AppFocusRingVariant.standard => colors.focusRing,
      AppFocusRingVariant.ai => colors.focusRingAi,
    };
  }

  BorderRadius? _outerRadius(BorderRadius? inner) {
    if (inner == null) return null;
    const expand = Radius.circular(_outerInset);
    return BorderRadius.only(
      topLeft: inner.topLeft + expand,
      topRight: inner.topRight + expand,
      bottomLeft: inner.bottomLeft + expand,
      bottomRight: inner.bottomRight + expand,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final duration = reduced ? AppDurations.instant : AppDurations.fast;
    final ringColor = _ringColor(context);

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          left: -_outerInset,
          top: -_outerInset,
          right: -_outerInset,
          bottom: -_outerInset,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: duration,
              decoration: BoxDecoration(
                borderRadius: _outerRadius(borderRadius),
                border: Border.all(
                  color: visible
                      ? ringColor
                      : ringColor.withValues(alpha: 0),
                  width: _ringWidth,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
