import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// RTL-aware inline-start 12px→0 + fade (motion-slide-inline).
class AppSlideInline extends StatefulWidget {
  const AppSlideInline({required this.child, super.key, this.delay = Duration.zero, this.offset = 12});

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<AppSlideInline> createState() => _AppSlideInlineState();
}

class _AppSlideInlineState extends State<AppSlideInline> with SingleTickerProviderStateMixin {
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
    final spec = AppMotion.resolvePreset(AppMotionPreset.slideInline, reduced: reduced);
    _controller = AnimationController(vsync: this, duration: spec.duration);
    final curve = CurvedAnimation(parent: _controller, curve: spec.curve);
    _opacity = curve;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final dx = reduced ? 0.0 : (isRtl ? -widget.offset : widget.offset);
    _slide = Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero).animate(curve);
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
