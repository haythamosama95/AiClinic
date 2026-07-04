import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// Height 0→auto + fade (motion-collapse).
class AppCollapse extends StatefulWidget {
  const AppCollapse({required this.child, super.key, this.expanded = true});

  final Widget child;
  final bool expanded;

  @override
  State<AppCollapse> createState() => _AppCollapseState();
}

class _AppCollapseState extends State<AppCollapse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _heightFactor;
  var _motionReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) {
      return;
    }
    _motionReady = true;
    final reduced = AppMotion.reduced(context);
    final spec = AppMotion.resolvePreset(AppMotionPreset.collapse, reduced: reduced);
    _controller = AnimationController(vsync: this, duration: spec.duration);
    final curve = CurvedAnimation(parent: _controller, curve: spec.curve);
    _opacity = curve;
    _heightFactor = curve;
    if (widget.expanded) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant AppCollapse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      if (widget.expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Align(
            alignment: Alignment.topCenter,
            heightFactor: _heightFactor.value.clamp(0.001, 1.0),
            child: Opacity(opacity: _opacity.value, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}
