import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

enum AppSignalVariant { standard, ai }

enum AppSignalSize { defaultSize, hero }

/// Signature active indicator — nav, command bar, AI thinking pulse (`04-components` C1).
class AppSignal extends StatefulWidget {
  const AppSignal({
    this.variant = AppSignalVariant.standard,
    this.orientation = Axis.horizontal,
    this.size = AppSignalSize.defaultSize,
    this.thinking = false,
    this.active = true,
    super.key,
  });

  final AppSignalVariant variant;
  final Axis orientation;
  final AppSignalSize size;
  final bool thinking;
  final bool active;

  @override
  State<AppSignal> createState() => _AppSignalState();
}

class _AppSignalState extends State<AppSignal> with SingleTickerProviderStateMixin {
  static const _thickness = 2.0;
  static const _thicknessHero = 3.0;

  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _syncPulseController();
  }

  @override
  void didUpdateWidget(covariant AppSignal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thinking != widget.thinking || oldWidget.variant != widget.variant) {
      _syncPulseController();
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  void _syncPulseController() {
    final shouldPulse = widget.thinking && widget.variant == AppSignalVariant.ai;
    if (shouldPulse && _pulseController == null) {
      _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
      _pulseAnimation = CurvedAnimation(parent: _pulseController!, curve: AppMotionEasing.linear);
    } else if (!shouldPulse && _pulseController != null) {
      _pulseController!.dispose();
      _pulseController = null;
      _pulseAnimation = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = widget.variant == AppSignalVariant.ai ? colors.signalColorAi : colors.signalColor;
    final thickness = widget.size == AppSignalSize.hero ? _thicknessHero : _thickness;
    final isHorizontal = widget.orientation == Axis.horizontal;
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    Widget signal(double opacity, List<BoxShadow> shadows, BoxConstraints constraints) {
      final width = isHorizontal ? (constraints.hasBoundedWidth ? constraints.maxWidth : thickness) : thickness;
      final height = isHorizontal ? thickness : (constraints.hasBoundedHeight ? constraints.maxHeight : thickness);

      return DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(AppRadius.full),
          boxShadow: shadows,
        ),
        child: SizedBox(width: width, height: height),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.thinking && widget.variant == AppSignalVariant.ai && !reducedMotion && _pulseAnimation != null) {
          return AnimatedBuilder(
            animation: _pulseAnimation!,
            builder: (context, child) {
              final t = _pulseAnimation!.value;
              final opacity = 0.5 + 0.5 * (1 - (2 * (t - 0.5)).abs());
              final glowStrength = t < 0.5 ? t * 2 : (1 - t) * 2;
              final shadows = widget.active
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35 + glowStrength * 0.1),
                        blurRadius: 8 + glowStrength * 4,
                      ),
                    ]
                  : const <BoxShadow>[];
              return signal(opacity, shadows, constraints);
            },
          );
        }

        final shadows = widget.active && !reducedMotion
            ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8)]
            : const <BoxShadow>[];

        return signal(1, shadows, constraints);
      },
    );
  }
}
