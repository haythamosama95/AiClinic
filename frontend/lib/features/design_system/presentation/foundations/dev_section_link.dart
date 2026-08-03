import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'dev_section_registry.dart';

/// Scroll-to-section link matching web `DevSectionLink`.
class DevSectionLink extends StatelessWidget {
  const DevSectionLink({
    required this.sectionId,
    required this.child,
    this.padding,
    super.key,
  });

  final String sectionId;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => DevSectionRegistry.scrollToSection(context, sectionId),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: DefaultTextStyle(
            style: AppTypography.bodySm(context).copyWith(color: colors.textLink),
            child: child,
          ),
        ),
      ),
    );
  }
}
