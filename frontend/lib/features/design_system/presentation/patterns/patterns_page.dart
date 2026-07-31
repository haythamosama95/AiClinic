import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_link.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/foundation_constants.dart';
import 'package:ai_clinic/features/design_system/presentation/patterns/pattern_registry.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_text_styles.dart';

/// Patterns tab content (web `PatternsPage`).
class PatternsPage extends StatelessWidget {
  const PatternsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PatternsIntro(),
        const SizedBox(height: AppSpacing.space16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= FoundationBreakpoints.lg) {
              return const SizedBox.shrink();
            }
            return Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                for (final section in patternSections)
                  DevSectionLink(
                    sectionId: section.id,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space1),
                    child: Text(section.title),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.space10),
        for (final section in patternSections) ...[section.builder(), const SizedBox(height: AppSpacing.space16)],
      ],
    );
  }
}

class PatternsSubNav extends StatelessWidget {
  const PatternsSubNav({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Patterns', style: DevTextStyles.overline(context)),
        const SizedBox(height: AppSpacing.space2),
        for (final section in patternSections)
          DevSectionLink(
            sectionId: section.id,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(section.title, style: AppTypography.caption(context)),
          ),
      ],
    );
  }
}

class _PatternsIntro extends StatelessWidget {
  const _PatternsIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Milestone 5', style: DevTextStyles.overline(context)),
        Text('Patterns', style: DevTextStyles.h2(context)),
        const SizedBox(height: AppSpacing.space2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 672),
          child: Text(
            'Composed demos from 05 — realistic mocked compositions built from shared components.',
            style: DevTextStyles.bodyLg(context),
          ),
        ),
      ],
    );
  }
}
