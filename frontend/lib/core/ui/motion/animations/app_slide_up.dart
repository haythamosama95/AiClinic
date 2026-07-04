import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// TranslateY 8px→0 + fade on mount (motion-slide-up).
class AppSlideUp extends StatefulWidget {
  const AppSlideUp({required this.child, super.key, this.delay = Duration.zero, this.offset = 8});

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<AppSlideUp> createState() => _AppSlideUpState();
}

class _AppSlideUpState extends State<AppSlideUp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  var _motionReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) {
      return;
    }
    _motionReady = true;
    final reduced = AppMotion.reduced(context);
    final spec = AppMotion.resolvePreset(AppMotionPreset.slideUp, reduced: reduced);
    _controller = AnimationController(vsync: this, duration: spec.duration);
    final curve = CurvedAnimation(parent: _controller, curve: spec.curve);
    _opacity = curve;
    _slide = Tween<Offset>(begin: Offset(0, reduced ? 0 : widget.offset), end: Offset.zero).animate(curve);
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
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
