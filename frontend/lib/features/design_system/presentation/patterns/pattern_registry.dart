import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/patterns/list_index_pattern.dart';
import 'package:ai_clinic/features/design_system/presentation/patterns/pattern_frame.dart';
import 'package:ai_clinic/features/design_system/presentation/patterns/state_gallery_pattern.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/showcase_primitives.dart';

class PatternSectionDef {
  const PatternSectionDef({required this.id, required this.title, required this.builder, this.description});

  final String id;
  final String title;
  final String? description;
  final Widget Function() builder;
}

final patternSections = <PatternSectionDef>[
  PatternSectionDef(
    id: 'pattern-list-index',
    title: 'List / Index',
    description: 'Toolbar, table, pagination, bulk actions.',
    builder: ListIndexPattern.new,
  ),
  PatternSectionDef(
    id: 'pattern-master-detail',
    title: 'Master–Detail',
    description: 'Split list with detail drawer.',
    builder: () => const _PatternPlaceholder(
      id: 'pattern-master-detail',
      title: 'Master–Detail',
      componentName: '05 §3 Master–Detail',
      description: 'Split list with detail drawer.',
    ),
  ),
  PatternSectionDef(
    id: 'pattern-editor-form',
    title: 'Editor / Form',
    description: 'Service editor with branch matrix and validation.',
    builder: () => const _PatternPlaceholder(
      id: 'pattern-editor-form',
      title: 'Editor / Form',
      componentName: '05 §4 Editor / Form',
      description: 'Service editor with branch matrix and validation.',
    ),
  ),
  PatternSectionDef(
    id: 'pattern-record-detail',
    title: 'Record Detail',
    description: 'Tabs, description lists, related data.',
    builder: () => const _PatternPlaceholder(
      id: 'pattern-record-detail',
      title: 'Record Detail',
      componentName: '05 §5 Record Detail',
      description: 'Tabs, description lists, related data.',
    ),
  ),
  PatternSectionDef(
    id: 'pattern-workspace',
    title: 'Workspace',
    description: 'Multi-pane encounter with dockable AI.',
    builder: () => const _PatternPlaceholder(
      id: 'pattern-workspace',
      title: 'Workspace',
      componentName: '05 §7 Workspace',
      description: 'Multi-pane encounter with dockable AI.',
    ),
  ),
  PatternSectionDef(
    id: 'pattern-calendar-queue',
    title: 'Calendar / Queue',
    description: 'Day schedule and queue board.',
    builder: () => const _PatternPlaceholder(
      id: 'pattern-calendar-queue',
      title: 'Calendar / Queue',
      componentName: '05 §8 Calendar / Queue',
      description: 'Day schedule and queue board.',
    ),
  ),
  PatternSectionDef(
    id: 'pattern-dashboard',
    title: 'Dashboard',
    description: 'Metrics, charts, and detail table.',
    builder: () => const _PatternPlaceholder(
      id: 'pattern-dashboard',
      title: 'Dashboard',
      componentName: '05 §9 Dashboard',
      description: 'Metrics, charts, and detail table.',
    ),
  ),
  PatternSectionDef(
    id: 'pattern-wizard',
    title: 'Wizard',
    description: 'Multi-step branch setup.',
    builder: () => const _PatternPlaceholder(
      id: 'pattern-wizard',
      title: 'Wizard',
      componentName: '05 §10 Wizard',
      description: 'Multi-step branch setup.',
    ),
  ),
  PatternSectionDef(
    id: 'pattern-ai-flow',
    title: 'AI flow',
    description: 'Ask, stream, approve, toast.',
    builder: () => const _PatternPlaceholder(
      id: 'pattern-ai-flow',
      title: 'AI flow',
      componentName: '05 §11 AI flow',
      description: 'Ask, stream, approve, toast.',
    ),
  ),
  PatternSectionDef(
    id: 'pattern-state-gallery',
    title: 'State gallery',
    description: 'Loading, empty, error, access, degraded.',
    builder: StateGalleryPattern.new,
  ),
];

class _PatternPlaceholder extends StatelessWidget {
  const _PatternPlaceholder({
    required this.id,
    required this.title,
    required this.componentName,
    required this.description,
  });

  final String id;
  final String title;
  final String componentName;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ShowcaseSection(
      id: id,
      title: title,
      componentName: componentName,
      description: description,
      child: PatternFrame(
        minHeight: 240,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space8),
            child: Text(
              'Pattern demo coming soon',
              style: AppTypography.body(context).copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
