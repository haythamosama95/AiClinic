import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/animations/app_slide_up.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// Staggers up to [maxItems] children with 20ms step (motion-row-enter).
class AppStagger extends StatelessWidget {
  const AppStagger({
    required this.children,
    super.key,
    this.maxItems = 6,
    this.stepMs = 20,
    this.builder = _defaultBuilder,
  });

  final List<Widget> children;
  final int maxItems;
  final int stepMs;
  final Widget Function(Widget child, Duration delay) builder;

  static Widget _defaultBuilder(Widget child, Duration delay) {
    return AppSlideUp(delay: delay, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final count = children.length.clamp(0, maxItems);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++)
          builder(children[i], AppMotion.staggerDelay(i, stepMs: stepMs)),
        ...children.skip(count),
      ],
    );
  }
}

/// Returns stagger delay for an item index (≤6 items @ 20ms).
Duration appStaggerDelay(int index, {int stepMs = 20}) {
  return AppMotion.staggerDelay(index, stepMs: stepMs);
}
