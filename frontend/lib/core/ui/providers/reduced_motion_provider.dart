import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User-toggleable reduced-motion preference for the design system showcase.
/// Combines with [MediaQuery.disableAnimations] at usage sites.
class ReducedMotionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setReducedMotion(bool value) => state = value;
  void toggle() => state = !state;
}

final reducedMotionProvider = NotifierProvider<ReducedMotionNotifier, bool>(
  ReducedMotionNotifier.new,
);
