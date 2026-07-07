import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// Page enter/exit motion values (web `PageTransition`).
abstract final class AppPageTransitionMotion {
  static const duration = Duration(milliseconds: 250);
  static const curve = Cubic(0.22, 1, 0.36, 1);

  static const enterOffsetY = 12.0;
  static const exitOffsetY = -8.0;

  static AppMotionValues valuesFor(double progress, {required bool exiting}) {
    final clamped = progress.clamp(0.0, 1.0);

    if (exiting) {
      // Exit is driven by controller.reverse (1 → 0): visible at 1, hidden at 0.
      return AppMotionValues(opacity: clamped, scale: 1, offset: Offset(0, ui.lerpDouble(exitOffsetY, 0, clamped)!));
    }

    // Enter is driven by controller.forward (0 → 1): hidden at 0, visible at 1.
    return AppMotionValues(opacity: clamped, scale: 1, offset: Offset(0, ui.lerpDouble(enterOffsetY, 0, clamped)!));
  }

  static Widget build({required double progress, required Widget child, required bool exiting}) {
    final values = valuesFor(progress, exiting: exiting);
    final opacity = values.opacity.clamp(0.0, 1.0);

    // Drop the outgoing page from the tree once fully hidden to prevent ghost frames.
    if (opacity <= 0 && exiting) {
      return const SizedBox.shrink();
    }

    return Opacity(
      opacity: opacity,
      child: Transform.translate(offset: values.offset, child: child),
    );
  }
}

/// Wraps page content with the standard shell enter animation (web `PageTransition`).
///
/// When used inside [ShellPageTransition], prefer letting the shell drive motion;
/// this widget is for standalone pages or nested content that animates on mount.
class AppPageTransition extends StatefulWidget {
  const AppPageTransition({required this.child, super.key});

  final Widget child;

  @override
  State<AppPageTransition> createState() => _AppPageTransitionState();
}

class _AppPageTransitionState extends State<AppPageTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppPageTransitionMotion.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (AppMotion.prefersReducedMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.prefersReducedMotion(context)) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: CurvedAnimation(parent: _controller, curve: AppPageTransitionMotion.curve),
      builder: (context, child) {
        return AppPageTransitionMotion.build(progress: _controller.value, exiting: false, child: child!);
      },
      child: widget.child,
    );
  }
}
