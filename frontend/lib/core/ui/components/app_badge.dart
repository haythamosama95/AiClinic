import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Application-owned badge (`04-components` D4).
class AppBadge extends StatelessWidget {
  const AppBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label, style: AppTypography.bodySm(context).copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }
}
