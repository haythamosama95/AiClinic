import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/component_registry.dart';
import 'package:ai_clinic/features/design_system/presentation/components/component_section_builders.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_link.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_registry.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/foundation_constants.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_text_styles.dart';

/// All component showcase sections (web `ComponentsPage`).
class ComponentsContent extends StatefulWidget {
  const ComponentsContent({this.progressive = false, this.onLoadComplete, super.key});

  /// When true, component groups are added one frame at a time so the UI stays responsive.
  final bool progressive;

  final VoidCallback? onLoadComplete;

  @override
  State<ComponentsContent> createState() => _ComponentsContentState();
}

class _ComponentsContentState extends State<ComponentsContent> {
  static const _sectionGap = AppSpacing.space16;
  static const _groupGap = AppSpacing.space10;

  late final Map<ShowcaseGroupId, List<ShowcaseSectionDef>> _grouped;
  late final List<ShowcaseGroupDef> _groupsWithContent;
  var _visibleGroupCount = 0;

  @override
  void initState() {
    super.initState();
    _grouped = groupedComponentSections;
    _groupsWithContent = [
      for (final group in showcaseGroups)
        if (_grouped[group.id]!.isNotEmpty) group,
    ];

    if (widget.progressive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadNextGroup());
    } else {
      _visibleGroupCount = _groupsWithContent.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoadComplete?.call());
    }
  }

  void _loadNextGroup() {
    if (!mounted) return;

    if (_visibleGroupCount >= _groupsWithContent.length) {
      widget.onLoadComplete?.call();
      return;
    }

    setState(() => _visibleGroupCount++);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNextGroup());
  }

  @override
  Widget build(BuildContext context) {
    final visibleGroups = _groupsWithContent.take(_visibleGroupCount);

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
                  for (final group in visibleGroups)
                    DevSectionLink(
                      sectionId: showcaseGroupSectionId(group.id),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 6),
                      child: Text(group.title),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.space8),
            ],
            for (final group in visibleGroups) ...[
              _ComponentGroup(group: group, sections: _grouped[group.id]!),
              const SizedBox(height: _sectionGap),
            ],
          ],
        );
      },
    );
  }
}

class _ComponentGroup extends StatelessWidget {
  const _ComponentGroup({required this.group, required this.sections});

  final ShowcaseGroupDef group;
  final List<ShowcaseSectionDef> sections;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return KeyedSubtree(
      key: DevSectionRegistry.keyFor(showcaseGroupSectionId(group.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.title, style: DevTextStyles.h2(context)),
                  const SizedBox(height: AppSpacing.space1),
                  Text(group.description, style: AppTypography.body(context).copyWith(color: colors.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: _ComponentsContentState._groupGap),
          for (var i = 0; i < sections.length; i++) ...[
            Opacity(
              opacity: sections[i].status == ShowcaseSectionStatus.placeholder ? 0.8 : 1,
              child: buildComponentSection(sections[i]),
            ),
            if (i < sections.length - 1) const SizedBox(height: _ComponentsContentState._sectionGap),
          ],
        ],
      ),
    );
  }
}
