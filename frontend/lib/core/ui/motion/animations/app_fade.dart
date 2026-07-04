import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// Opacity 0→1 on mount (motion-fade).
class AppFade extends StatefulWidget {
  const AppFade({required this.child, super.key, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<AppFade> createState() => _AppFadeState();
}

class _AppFadeState extends State<AppFade> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  var _motionReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) {
      return;
    }
    _motionReady = true;
    final reduced = AppMotion.reduced(context);
    final spec = AppMotion.resolvePreset(AppMotionPreset.fade, reduced: reduced);
    _controller = AnimationController(vsync: this, duration: spec.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: spec.curve);
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}
