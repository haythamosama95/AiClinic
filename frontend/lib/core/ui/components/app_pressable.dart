import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// Press-scale wrapper for interactive controls (web `active:scale-[0.98]`).
class AppPressable extends StatefulWidget {
  const AppPressable({
    required this.child,
    this.onPressed,
    this.enabled = true,
    this.onPressedChanged,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool enabled;
  final ValueChanged<bool>? onPressedChanged;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  var _pressed = false;

  bool get _canPress => widget.enabled && widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final scale = _pressed && _canPress && !reducedMotion ? 0.98 : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _canPress
          ? (_) {
              setState(() => _pressed = true);
              widget.onPressedChanged?.call(true);
            }
          : null,
      onTapUp: _canPress
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressedChanged?.call(false);
            }
          : null,
      onTapCancel: _canPress
          ? () {
              setState(() => _pressed = false);
              widget.onPressedChanged?.call(false);
            }
          : null,
      onTap: _canPress ? widget.onPressed : null,
      child: AnimatedScale(
        scale: scale,
        duration: AppMotion.instant,
        curve: AppMotion.standardCurve,
        child: widget.child,
      ),
    );
  }
}
