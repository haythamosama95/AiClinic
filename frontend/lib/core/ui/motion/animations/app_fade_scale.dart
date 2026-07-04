import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// Opacity + scale 0.98→1 on mount (motion-fade-scale).
class AppFadeScale extends StatefulWidget {
  const AppFadeScale({required this.child, super.key, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<AppFadeScale> createState() => _AppFadeScaleState();
}

class _AppFadeScaleState extends State<AppFadeScale> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  var _motionReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) {
      return;
    }
    _motionReady = true;
    final reduced = AppMotion.reduced(context);
    final spec = AppMotion.resolvePreset(AppMotionPreset.fadeScale, reduced: reduced);
    _controller = AnimationController(vsync: this, duration: spec.duration);
    final curve = CurvedAnimation(parent: _controller, curve: spec.curve);
    _opacity = curve;
    _scale = Tween<double>(begin: reduced ? 1 : 0.98, end: 1).animate(curve);
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
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
