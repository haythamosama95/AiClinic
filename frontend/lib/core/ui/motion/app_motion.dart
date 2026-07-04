import 'package:flutter/material.dart';

/// Motion duration tokens matching the web design system.
abstract final class AppDurations {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration deliberate = Duration(milliseconds: 480);

  /// Reduced-motion overrides from index.css.
  static const Duration reducedQuick = Duration(milliseconds: 80);
}

/// Motion easing curves matching the web cubic-bezier tokens.
abstract final class AppCurves {
  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve out = Cubic(0.16, 1, 0.3, 1);
  static const Curve easeIn = Cubic(0.4, 0, 1, 1);
  static const Curve inOut = Cubic(0.65, 0, 0.35, 1);
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve linear = Curves.linear;
}

/// Named motion presets from the web `motionPresets`.
enum AppMotionPreset {
  fade,
  fadeScale,
  slideUp,
  slideInline,
  modal,
  drawer,
  command,
  collapse,
  tab,
  nav,
  rowEnter,
}

/// Configuration for a motion preset's timing.
class AppMotionTransition {
  const AppMotionTransition({required this.duration, required this.curve});

  final Duration duration;
  final Curve curve;
}

/// Motion helpers — durations, curves, presets, and reduced-motion resolution.
abstract final class AppMotion {
  static bool isReducedMotion(BuildContext context, {bool? override}) {
    if (override != null) return override;
    return MediaQuery.disableAnimationsOf(context);
  }

  static AppMotionTransition resolveTransition({
    required AppMotionPreset preset,
    required bool reducedMotion,
  }) {
    final config = _presetConfig[preset]!;
    if (reducedMotion) {
      return AppMotionTransition(
        duration: config.ease == AppCurves.easeIn
            ? Duration.zero
            : AppDurations.fast,
        curve: AppCurves.standard,
      );
    }
    return AppMotionTransition(duration: config.duration, curve: config.ease);
  }

  static AppMotionTransition resolve({
    required Duration duration,
    required Curve curve,
    required bool reducedMotion,
    bool isEaseIn = false,
  }) {
    if (reducedMotion) {
      return AppMotionTransition(
        duration: isEaseIn ? Duration.zero : AppDurations.fast,
        curve: AppCurves.standard,
      );
    }
    return AppMotionTransition(duration: duration, curve: curve);
  }

  /// Returns initial offset/scale/opacity for [preset] hidden state.
  static AppMotionValues hiddenValues(
    AppMotionPreset preset, {
    required TextDirection direction,
  }) {
    final inlineStart = direction == TextDirection.rtl ? -12.0 : 12.0;
    return switch (preset) {
      AppMotionPreset.fade => const AppMotionValues(opacity: 0),
      AppMotionPreset.fadeScale => const AppMotionValues(
        opacity: 0,
        scale: 0.98,
      ),
      AppMotionPreset.slideUp => const AppMotionValues(opacity: 0, dy: 8),
      AppMotionPreset.slideInline => AppMotionValues(
        opacity: 0,
        dx: inlineStart,
      ),
      AppMotionPreset.modal => const AppMotionValues(
        opacity: 0,
        scale: 0.97,
        dy: 8,
      ),
      AppMotionPreset.drawer => AppMotionValues(
        dx: direction == TextDirection.rtl ? -1 : 1,
        drawerFraction: true,
      ),
      AppMotionPreset.command => const AppMotionValues(
        opacity: 0,
        scale: 0.96,
        dy: 10,
      ),
      AppMotionPreset.collapse => const AppMotionValues(
        opacity: 0,
        heightFactor: 0,
      ),
      AppMotionPreset.tab => const AppMotionValues(scaleX: 0),
      AppMotionPreset.nav => const AppMotionValues(opacity: 0.6),
      AppMotionPreset.rowEnter => const AppMotionValues(opacity: 0, dy: 6),
    };
  }

  static const AppMotionValues visibleValues = AppMotionValues();

  /// Stagger delay per child in milliseconds (web default: 20ms).
  static Duration staggerDelay(int index, {int stepMs = 20}) {
    return Duration(milliseconds: index * stepMs);
  }

  static const buttonPressScale = 0.98;

  static const Map<AppMotionPreset, _PresetConfig> _presetConfig = {
    AppMotionPreset.fade: _PresetConfig(AppDurations.base, AppCurves.standard),
    AppMotionPreset.fadeScale: _PresetConfig(AppDurations.quick, AppCurves.out),
    AppMotionPreset.slideUp: _PresetConfig(AppDurations.base, AppCurves.out),
    AppMotionPreset.slideInline: _PresetConfig(
      AppDurations.base,
      AppCurves.out,
    ),
    AppMotionPreset.modal: _PresetConfig(AppDurations.base, AppCurves.out),
    AppMotionPreset.drawer: _PresetConfig(
      AppDurations.slow,
      AppCurves.standard,
    ),
    AppMotionPreset.command: _PresetConfig(
      AppDurations.quick,
      AppCurves.emphasized,
    ),
    AppMotionPreset.collapse: _PresetConfig(
      AppDurations.quick,
      AppCurves.standard,
    ),
    AppMotionPreset.tab: _PresetConfig(AppDurations.quick, AppCurves.inOut),
    AppMotionPreset.nav: _PresetConfig(AppDurations.quick, AppCurves.inOut),
    AppMotionPreset.rowEnter: _PresetConfig(AppDurations.base, AppCurves.out),
  };
}

class _PresetConfig {
  const _PresetConfig(this.duration, this.ease);
  final Duration duration;
  final Curve ease;
}

/// Animated property values for motion presets.
@immutable
class AppMotionValues {
  const AppMotionValues({
    this.opacity = 1,
    this.scale = 1,
    this.scaleX = 1,
    this.dx = 0,
    this.dy = 0,
    this.heightFactor = 1,
    this.drawerFraction = false,
  });

  final double opacity;
  final double scale;
  final double scaleX;
  final double dx;
  final double dy;
  final double heightFactor;
  final bool drawerFraction;

  AppMotionValues lerp(AppMotionValues other, double t) {
    return AppMotionValues(
      opacity: _lerp(opacity, other.opacity, t),
      scale: _lerp(scale, other.scale, t),
      scaleX: _lerp(scaleX, other.scaleX, t),
      dx: _lerp(dx, other.dx, t),
      dy: _lerp(dy, other.dy, t),
      heightFactor: _lerp(heightFactor, other.heightFactor, t),
      drawerFraction: t < 0.5 ? drawerFraction : other.drawerFraction,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// Widget that animates between hidden and visible using a motion preset.
class AppMotionPresetAnimator extends StatefulWidget {
  const AppMotionPresetAnimator({
    super.key,
    required this.preset,
    required this.child,
    this.reducedMotion = false,
    this.replayKey = 0,
  });

  final AppMotionPreset preset;
  final Widget child;
  final bool reducedMotion;
  final int replayKey;

  @override
  State<AppMotionPresetAnimator> createState() =>
      _AppMotionPresetAnimatorState();
}

class _AppMotionPresetAnimatorState extends State<AppMotionPresetAnimator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.linear);
    _runAnimation();
  }

  @override
  void didUpdateWidget(AppMotionPresetAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preset != widget.preset ||
        oldWidget.replayKey != widget.replayKey) {
      _runAnimation();
    }
  }

  void _runAnimation() {
    final transition = AppMotion.resolveTransition(
      preset: widget.preset,
      reducedMotion: widget.reducedMotion,
    );
    _controller.duration = transition.duration;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final hidden = AppMotion.hiddenValues(widget.preset, direction: direction);
    final visible = AppMotion.visibleValues;
    final transition = AppMotion.resolveTransition(
      preset: widget.preset,
      reducedMotion: widget.reducedMotion,
    );

    return AnimatedBuilder(
      animation: CurvedAnimation(parent: _controller, curve: transition.curve),
      builder: (context, child) {
        final t = _animation.value;
        final values = hidden.lerp(visible, t);
        final dx = values.drawerFraction
            ? values.dx * MediaQuery.sizeOf(context).width
            : values.dx;
        return Opacity(
          opacity: values.opacity,
          child: Transform.translate(
            offset: Offset(dx, values.dy),
            child: Transform.scale(
              scaleX: values.scale * values.scaleX,
              scaleY: values.scale,
              alignment: widget.preset == AppMotionPreset.tab
                  ? Alignment.centerLeft
                  : Alignment.center,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
