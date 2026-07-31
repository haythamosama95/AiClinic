import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/component_registry.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_link.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_text_styles.dart';

/// Side navigation for component groups (web `ComponentsSubNav`).
class ComponentsSubNav extends StatelessWidget {
  const ComponentsSubNav({super.key});

  @override
  Widget build(BuildContext context) {
    final grouped = groupedComponentSections;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Component groups', style: DevTextStyles.overline(context)),
        const SizedBox(height: AppSpacing.space2),
        for (final group in showcaseGroups) ...[
          if (grouped[group.id]!.isNotEmpty) ...[
            _GroupNavItem(group: group, sections: grouped[group.id]!),
            const SizedBox(height: AppSpacing.space3),
          ],
        ],
      ],
    );
  }
}

class _GroupNavItem extends StatelessWidget {
  const _GroupNavItem({
    required this.group,
    required this.sections,
  });

  final ShowcaseGroupDef group;
  final List<ShowcaseSectionDef> sections;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final readyCount = sections.where((s) => s.status == ShowcaseSectionStatus.ready).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DevSectionLink(
          sectionId: showcaseGroupSectionId(group.id),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space1),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: group.title),
                TextSpan(
                  text: ' ($readyCount/${sections.length})',
                  style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsetsDirectional.only(start: AppSpacing.space2, top: AppSpacing.space1),
          padding: const EdgeInsetsDirectional.only(start: AppSpacing.space3),
          decoration: BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: colors.borderSubtle, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in sections)
                DevSectionLink(
                  sectionId: section.id,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    section.title,
                    style: AppTypography.caption(context).copyWith(
                      color: section.status == ShowcaseSectionStatus.ready
                          ? colors.textSecondary
                          : colors.textTertiary,
                      fontStyle: section.status == ShowcaseSectionStatus.placeholder
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
