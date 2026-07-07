import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Motion duration tokens in milliseconds (`03-motion`).
abstract final class AppMotionDuration {
  static const instant = Duration(milliseconds: 80);
  static const fast = Duration(milliseconds: 120);
  static const quick = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
  static const deliberate = Duration(milliseconds: 480);
}

/// Motion easing curves matching web CSS cubic-bezier tokens.
abstract final class AppMotionEasing {
  static const standard = Cubic(0.2, 0, 0, 1);
  static const out = Cubic(0.16, 1, 0.3, 1);
  static const inCurve = Cubic(0.4, 0, 1, 1);
  static const inOut = Cubic(0.65, 0, 0.35, 1);
  static const emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve linear = Curves.linear;
}

enum AppMotionPreset {
  fade,
  fadeScale,
  slideUp,
  slideInline,
  modal,
  drawer,
  command,
  rowEnter,
}

/// Resolved motion values for a preset at a given animation progress.
@immutable
class AppMotionValues {
  const AppMotionValues({
    required this.opacity,
    required this.scale,
    required this.offset,
  });

  final double opacity;
  final double scale;
  final Offset offset;

  static const visible = AppMotionValues(opacity: 1, scale: 1, offset: Offset.zero);
}

/// Application-owned motion presets aligned with `web-reference/src/lib/motion.ts`.
abstract final class AppMotion {
  static const instant = AppMotionDuration.instant;
  static const fast = AppMotionDuration.fast;
  static const quick = AppMotionDuration.quick;
  static const base = AppMotionDuration.base;
  static const slow = AppMotionDuration.slow;
  static const deliberate = AppMotionDuration.deliberate;

  static const standardCurve = AppMotionEasing.standard;
  static const outCurve = AppMotionEasing.out;
  static const inCurve = AppMotionEasing.inCurve;
  static const inOutCurve = AppMotionEasing.inOut;
  static const emphasizedCurve = AppMotionEasing.emphasized;
  static const linearCurve = AppMotionEasing.linear;

  static bool prefersReducedMotion(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context);
  }

  static Duration resolveDuration(AppMotionPreset preset, {bool reducedMotion = false}) {
    final config = _presetConfig(preset);
    if (reducedMotion) {
      return config.ease == AppMotionEasingToken.inCurve ? Duration.zero : AppMotionDuration.fast;
    }
    return switch (config.duration) {
      AppMotionDurationToken.instant => AppMotionDuration.instant,
      AppMotionDurationToken.fast => AppMotionDuration.fast,
      AppMotionDurationToken.quick => AppMotionDuration.quick,
      AppMotionDurationToken.base => AppMotionDuration.base,
      AppMotionDurationToken.slow => AppMotionDuration.slow,
      AppMotionDurationToken.deliberate => AppMotionDuration.deliberate,
    };
  }

  static Curve resolveCurve(AppMotionPreset preset, {bool reducedMotion = false}) {
    if (reducedMotion) {
      return AppMotionEasing.standard;
    }
    final config = _presetConfig(preset);
    return switch (config.ease) {
      AppMotionEasingToken.standard => AppMotionEasing.standard,
      AppMotionEasingToken.out => AppMotionEasing.out,
      AppMotionEasingToken.inCurve => AppMotionEasing.inCurve,
      AppMotionEasingToken.inOut => AppMotionEasing.inOut,
      AppMotionEasingToken.emphasized => AppMotionEasing.emphasized,
      AppMotionEasingToken.linear => AppMotionEasing.linear,
    };
  }

  static Duration resolveDurationFromTokens({
    required BuildContext context,
    required AppMotionDurationToken duration,
    AppMotionEasingToken ease = AppMotionEasingToken.standard,
  }) {
    if (prefersReducedMotion(context)) {
      return ease == AppMotionEasingToken.inCurve ? Duration.zero : AppMotionDuration.fast;
    }

    return switch (duration) {
      AppMotionDurationToken.instant => AppMotionDuration.instant,
      AppMotionDurationToken.fast => AppMotionDuration.fast,
      AppMotionDurationToken.quick => AppMotionDuration.quick,
      AppMotionDurationToken.base => AppMotionDuration.base,
      AppMotionDurationToken.slow => AppMotionDuration.slow,
      AppMotionDurationToken.deliberate => AppMotionDuration.deliberate,
    };
  }

  static Curve resolveCurveFromTokens({
    required BuildContext context,
    AppMotionEasingToken ease = AppMotionEasingToken.standard,
  }) {
    if (prefersReducedMotion(context)) {
      return AppMotionEasing.standard;
    }

    return switch (ease) {
      AppMotionEasingToken.standard => AppMotionEasing.standard,
      AppMotionEasingToken.out => AppMotionEasing.out,
      AppMotionEasingToken.inCurve => AppMotionEasing.inCurve,
      AppMotionEasingToken.inOut => AppMotionEasing.inOut,
      AppMotionEasingToken.emphasized => AppMotionEasing.emphasized,
      AppMotionEasingToken.linear => AppMotionEasing.linear,
    };
  }

  static ({Duration duration, Curve curve}) transitionFor({
    required BuildContext context,
    required AppMotionPreset preset,
  }) {
    final reduced = prefersReducedMotion(context);
    return (duration: resolveDuration(preset, reducedMotion: reduced), curve: resolveCurve(preset, reducedMotion: reduced));
  }

  static AppMotionValues hidden(AppMotionPreset preset, {TextDirection direction = TextDirection.ltr}) {
    return switch (preset) {
      AppMotionPreset.fade => const AppMotionValues(opacity: 0, scale: 1, offset: Offset.zero),
      AppMotionPreset.fadeScale => const AppMotionValues(opacity: 0, scale: 0.98, offset: Offset.zero),
      AppMotionPreset.slideUp => const AppMotionValues(opacity: 0, scale: 1, offset: Offset(0, 8)),
      AppMotionPreset.slideInline => AppMotionValues(
        opacity: 0,
        scale: 1,
        offset: Offset(direction == TextDirection.rtl ? -12 : 12, 0),
      ),
      AppMotionPreset.modal => const AppMotionValues(opacity: 0, scale: 0.97, offset: Offset(0, 8)),
      AppMotionPreset.drawer => AppMotionValues(
        opacity: 1,
        scale: 1,
        offset: Offset(direction == TextDirection.rtl ? -1 : 1, 0),
      ),
      AppMotionPreset.command => const AppMotionValues(opacity: 0, scale: 0.96, offset: Offset(0, 10)),
      AppMotionPreset.rowEnter => const AppMotionValues(opacity: 0, scale: 1, offset: Offset(0, 6)),
    };
  }

  static AppMotionValues lerpPreset({
    required AppMotionPreset preset,
    required double t,
    TextDirection direction = TextDirection.ltr,
  }) {
    final begin = hidden(preset, direction: direction);
    final end = AppMotionValues.visible;
    return AppMotionValues(
      opacity: ui.lerpDouble(begin.opacity, end.opacity, t)!,
      scale: ui.lerpDouble(begin.scale, end.scale, t)!,
      offset: Offset.lerp(begin.offset, end.offset, t)!,
    );
  }

  static Duration staggerStep(BuildContext context, {int stepMs = 20}) {
    if (prefersReducedMotion(context)) {
      return Duration.zero;
    }
    return Duration(milliseconds: stepMs);
  }

  static Widget animatedPreset({
    required BuildContext context,
    required AppMotionPreset preset,
    required Widget child,
    required Animation<double> animation,
  }) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final values = lerpPreset(
          preset: preset,
          t: animation.value,
          direction: Directionality.of(context),
        );
        return Opacity(
          opacity: values.opacity,
          child: Transform.translate(
            offset: values.offset,
            child: Transform.scale(scale: values.scale, child: child),
          ),
        );
      },
      child: child,
    );
  }

  static ({AppMotionDurationToken duration, AppMotionEasingToken ease}) _presetConfig(AppMotionPreset preset) {
    return switch (preset) {
      AppMotionPreset.fade => (duration: AppMotionDurationToken.base, ease: AppMotionEasingToken.standard),
      AppMotionPreset.fadeScale => (duration: AppMotionDurationToken.quick, ease: AppMotionEasingToken.out),
      AppMotionPreset.slideUp => (duration: AppMotionDurationToken.base, ease: AppMotionEasingToken.out),
      AppMotionPreset.slideInline => (duration: AppMotionDurationToken.base, ease: AppMotionEasingToken.out),
      AppMotionPreset.modal => (duration: AppMotionDurationToken.base, ease: AppMotionEasingToken.out),
      AppMotionPreset.drawer => (duration: AppMotionDurationToken.slow, ease: AppMotionEasingToken.standard),
      AppMotionPreset.command => (duration: AppMotionDurationToken.quick, ease: AppMotionEasingToken.emphasized),
      AppMotionPreset.rowEnter => (duration: AppMotionDurationToken.base, ease: AppMotionEasingToken.out),
    };
  }
}

enum AppMotionDurationToken { instant, fast, quick, base, slow, deliberate }

enum AppMotionEasingToken { standard, out, inCurve, inOut, emphasized, linear }
