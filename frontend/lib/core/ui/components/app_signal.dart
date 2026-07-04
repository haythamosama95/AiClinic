import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// The teal active indicator used in navigation (`04-components` C1).
class AppSignal extends StatelessWidget {
  const AppSignal({this.orientation = Axis.vertical, super.key});

  final Axis orientation;

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.signalColor;
    const thickness = 2.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.full),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6)],
      ),
      child: orientation == Axis.vertical ? const SizedBox(width: thickness) : const SizedBox(height: thickness),
    );
  }
}
