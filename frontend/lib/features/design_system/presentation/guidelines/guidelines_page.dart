import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_link.dart';
import 'package:ai_clinic/features/design_system/presentation/guidelines/accessibility_guidelines_showcase.dart';
import 'package:ai_clinic/features/design_system/presentation/guidelines/voice_guidelines_showcase.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/foundation_constants.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_text_styles.dart';

/// Guidelines tab content (web `GuidelinesPage`).
class GuidelinesPage extends StatelessWidget {
  const GuidelinesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _GuidelinesIntro(),
        const SizedBox(height: AppSpacing.space16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= FoundationBreakpoints.lg) {
              return const SizedBox.shrink();
            }
            return Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: const [
                DevSectionLink(
                  sectionId: 'guidelines-voice',
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space1),
                  child: Text('Voice'),
                ),
                DevSectionLink(
                  sectionId: 'guidelines-focus',
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space1),
                  child: Text('Accessibility'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.space10),
        const VoiceGuidelinesShowcase(),
        const SizedBox(height: AppSpacing.space16),
        const AccessibilityGuidelinesShowcase(),
      ],
    );
  }
}

class GuidelinesSubNav extends StatelessWidget {
  const GuidelinesSubNav({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Guidelines', style: DevTextStyles.overline(context)),
        const SizedBox(height: AppSpacing.space2),
        for (final item in _guidelineNavItems)
          DevSectionLink(
            sectionId: item.id,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              item.label,
              style: AppTypography.caption(context).copyWith(color: context.appColors.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _GuidelineNavItem {
  const _GuidelineNavItem({required this.id, required this.label});

  final String id;
  final String label;
}

const _guidelineNavItems = <_GuidelineNavItem>[
  _GuidelineNavItem(id: 'guidelines-voice', label: 'Voice & content'),
  _GuidelineNavItem(id: 'guidelines-focus', label: 'Accessibility'),
  _GuidelineNavItem(id: 'guidelines-contrast', label: 'Contrast'),
  _GuidelineNavItem(id: 'guidelines-keyboard', label: 'Keyboard'),
  _GuidelineNavItem(id: 'guidelines-reduced-motion', label: 'Reduced motion'),
];

class _GuidelinesIntro extends StatelessWidget {
  const _GuidelinesIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Milestone 5', style: DevTextStyles.overline(context)),
        Text('Content & guidelines', style: DevTextStyles.h2(context)),
        const SizedBox(height: AppSpacing.space2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 672),
          child: Text(
            'Voice examples from 08 and accessibility walkthrough from 07 — rendered reference, not prose docs.',
            style: DevTextStyles.bodyLg(context),
          ),
        ),
      ],
    );
  }
}
