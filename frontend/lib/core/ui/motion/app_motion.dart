import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/tokens/app_durations.dart';
import 'package:ai_clinic/core/ui/tokens/app_easings.dart';

/// Named motion presets mirroring the web reference.
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

class MotionPresetSpec {
  const MotionPresetSpec({required this.duration, required this.easing});

  final Duration duration;
  final Curve easing;
}

/// Whether the user prefers reduced motion. Override via [ReducedMotionScope].
final reducedMotionProvider = Provider<bool>((ref) => false);

/// Motion token resolver and preset registry.
abstract final class AppMotion {
  static const Map<AppMotionPreset, MotionPresetSpec> presets = {
    AppMotionPreset.fade: MotionPresetSpec(
      duration: AppDurations.base,
      easing: AppEasings.standard,
    ),
    AppMotionPreset.fadeScale: MotionPresetSpec(
      duration: AppDurations.quick,
      easing: AppEasings.out,
    ),
    AppMotionPreset.slideUp: MotionPresetSpec(
      duration: AppDurations.base,
      easing: AppEasings.out,
    ),
    AppMotionPreset.slideInline: MotionPresetSpec(
      duration: AppDurations.base,
      easing: AppEasings.out,
    ),
    AppMotionPreset.modal: MotionPresetSpec(
      duration: AppDurations.base,
      easing: AppEasings.out,
    ),
    AppMotionPreset.drawer: MotionPresetSpec(
      duration: AppDurations.slow,
      easing: AppEasings.standard,
    ),
    AppMotionPreset.command: MotionPresetSpec(
      duration: AppDurations.quick,
      easing: AppEasings.emphasized,
    ),
    AppMotionPreset.collapse: MotionPresetSpec(
      duration: AppDurations.quick,
      easing: AppEasings.standard,
    ),
    AppMotionPreset.tab: MotionPresetSpec(
      duration: AppDurations.quick,
      easing: AppEasings.inOut,
    ),
    AppMotionPreset.nav: MotionPresetSpec(
      duration: AppDurations.quick,
      easing: AppEasings.inOut,
    ),
    AppMotionPreset.rowEnter: MotionPresetSpec(
      duration: AppDurations.base,
      easing: AppEasings.out,
    ),
  };

  static bool reduced(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context);
  }

  /// Resolves a preset to duration + curve, respecting reduced motion.
  static ({Duration duration, Curve curve}) resolve(
    MotionPresetSpec preset, {
    bool? reduced,
    bool isExit = false,
  }) {
    final isReduced = reduced ?? false;
    if (isReduced) {
      return (
        duration: isExit ? Duration.zero : AppDurations.fast,
        curve: AppEasings.standard,
      );
    }
    return (duration: preset.duration, curve: preset.easing);
  }

  static ({Duration duration, Curve curve}) resolvePreset(
    AppMotionPreset preset, {
    bool? reduced,
    bool isExit = false,
  }) {
    return resolve(presets[preset]!, reduced: reduced, isExit: isExit);
  }

  static Duration staggerDelay(int index, {int stepMs = 20}) {
    return Duration(milliseconds: index * stepMs);
  }
}

/// Provides [reducedMotionProvider] from the widget tree's [MediaQuery].
class ReducedMotionScope extends ConsumerWidget {
  const ReducedMotionScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return ProviderScope(
      overrides: [reducedMotionProvider.overrideWithValue(reduced)],
      child: child,
    );
  }
}
