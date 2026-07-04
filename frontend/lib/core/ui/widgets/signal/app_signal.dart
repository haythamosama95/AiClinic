import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/theme_context.dart';
import 'package:ai_clinic/core/ui/tokens/app_durations.dart';
import 'package:ai_clinic/core/ui/tokens/app_radii.dart';
import 'package:ai_clinic/core/ui/tokens/app_signal_tokens.dart';

enum AppSignalOrientation { vertical, horizontal }

/// The Signal — thin luminous rounded line (nav indicator, tab underline, AI pulse).
class AppSignalLine extends StatefulWidget {
  const AppSignalLine({
    super.key,
    this.thickness = AppSignal.thickness,
    this.color,
    this.ai = false,
    this.orientation = AppSignalOrientation.vertical,
    this.glow = false,
    this.thinking = false,
    this.length,
  });

  final double thickness;
  final Color? color;
  final bool ai;
  final AppSignalOrientation orientation;
  final bool glow;
  final bool thinking;
  final double? length;

  @override
  State<AppSignalLine> createState() => _AppSignalLineState();
}

class _AppSignalLineState extends State<AppSignalLine> with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant AppSignalLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.thinking != oldWidget.thinking) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    final reduced = AppMotion.reduced(context);
    if (widget.thinking && !reduced) {
      _pulseController ??= AnimationController(vsync: this, duration: AppDurations.deliberate)..repeat();
    } else {
      _pulseController?.dispose();
      _pulseController = null;
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  Color _resolveColor(BuildContext context) {
    if (widget.color != null) return widget.color!;
    final colors = context.colors;
    return widget.ai ? colors.signalColorAi : colors.signalColor;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final baseColor = _resolveColor(context);
    final showGlow = widget.glow && !reduced;
    final shadows = showGlow ? AppSignal.glow(baseColor) : null;

    Widget line(Color color) {
      final isVertical = widget.orientation == AppSignalOrientation.vertical;
      return Container(
        width: isVertical ? widget.thickness : widget.length,
        height: isVertical ? widget.length : widget.thickness,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadii.full), boxShadow: shadows),
      );
    }

    if (_pulseController != null) {
      return AnimatedBuilder(
        animation: _pulseController!,
        builder: (context, child) {
          final t = _pulseController!.value;
          final luminance = 0.75 + 0.25 * (t < 0.5 ? t * 2 : (1 - t) * 2);
          final pulsed = Color.lerp(baseColor.withValues(alpha: 0.6), baseColor, luminance)!;
          return line(pulsed);
        },
      );
    }

    return line(baseColor);
  }
}
