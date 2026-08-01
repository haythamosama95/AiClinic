import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'dev_section_link.dart';
import 'foundation_constants.dart';

/// Side navigation list matching web `FoundationsSubNav`.
class FoundationsSubNav extends StatelessWidget {
  const FoundationsSubNav({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Foundations', style: AppTypography.overline(context)),
        const SizedBox(height: AppSpacing.space2),
        for (final section in foundationSections)
          DevSectionLink(
            sectionId: section.id,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space1),
            child: Text(section.label),
          ),
      ],
    );
  }
}
