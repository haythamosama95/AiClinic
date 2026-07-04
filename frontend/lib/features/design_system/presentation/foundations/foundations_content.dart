import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/color_section.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_link.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/foundation_constants.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/motion_section.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/signal_section.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/spacing_section.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/typography_section.dart';

/// All foundation sections (web `FoundationsContent`).
class FoundationsContent extends StatelessWidget {
  const FoundationsContent({super.key});

  static const _sectionGap = AppSpacing.space16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showMobileNav = constraints.maxWidth < FoundationBreakpoints.lg;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showMobileNav) ...[
              Wrap(
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                children: [
                  for (final section in foundationSections)
                    DevSectionLink(
                      sectionId: section.id,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 6),
                      child: Text(section.label),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.space8),
            ],
            const ColorSection(),
            const SizedBox(height: _sectionGap),
            const TypographySection(),
            const SizedBox(height: _sectionGap),
            const SpacingSection(),
            const SizedBox(height: _sectionGap),
            const MotionSection(),
            const SizedBox(height: _sectionGap),
            const SignalSection(),
          ],
        );
      },
    );
  }
}
