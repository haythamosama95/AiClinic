import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ThemeTransitionRunner = Future<void> Function(ThemeMode target, Offset origin);

/// Holds the active theme-transition runner without notifying Riverpod listeners.
final class ThemeTransitionRegistry {
  ThemeTransitionRunner? runner;
}

final themeTransitionRegistryProvider = Provider<ThemeTransitionRegistry>((ref) {
  return ThemeTransitionRegistry();
});

/// Stable key for the root [Navigator] so overlays can be reached from
/// [MaterialApp.builder], which sits above the navigator in the widget tree.
final rootNavigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  return GlobalKey<NavigatorState>();
});

/// Maximum circle radius that covers [viewport] when expanding from [origin].
double themeRevealMaxRadius(Offset origin, Size viewport) {
  final dx = math.max(origin.dx, viewport.width - origin.dx);
  final dy = math.max(origin.dy, viewport.height - origin.dy);
  return math.sqrt(dx * dx + dy * dy);
}
