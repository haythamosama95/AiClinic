import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/patterns/patterns.dart';
import 'package:ai_clinic/features/dev/presentation/widgets/showcase_section.dart';

/// Patterns tab — composed page templates from the design system.
class PatternsShowcaseSection extends ConsumerStatefulWidget {
  const PatternsShowcaseSection({super.key});

  @override
  ConsumerState<PatternsShowcaseSection> createState() => _PatternsShowcaseSectionState();
}

class _PatternsShowcaseSectionState extends ConsumerState<PatternsShowcaseSection> {
  var _galleryState = AppContentState.ready;

  static const _patternCatalog = [
    (
      'List / Index',
      'Toolbar, table, pagination, and bulk actions.',
      'pattern-list-index',
    ),
    (
      'Master–Detail',
      'Split list with detail drawer.',
      'pattern-master-detail',
    ),
    (
      'Editor / Form',
      'Branch matrix, validation, and save flows.',
      'pattern-editor-form',
    ),
    (
      'Record Detail',
      'Tabs, description lists, and related data.',
      'pattern-record-detail',
    ),
    (
      'Workspace',
      'Multi-pane encounter layout with dockable AI.',
      'pattern-workspace',
    ),
    (
      'Calendar / Queue',
      'Day schedule and queue board.',
      'pattern-calendar-queue',
    ),
    (
      'Dashboard',
      'Metrics, charts, and detail table.',
      'pattern-dashboard',
    ),
    (
      'Wizard',
      'Multi-step setup flow.',
      'pattern-wizard',
    ),
    (
      'AI flow',
      'Ask, stream, approve, and toast.',
      'pattern-ai-flow',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Milestone 5',
          style: typography.overline.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          'Patterns',
          style: typography.h2.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          'Composed page templates with mocked data — the building blocks feature screens assemble from.',
          style: typography.bodyLg.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        ShowcaseSection(
          title: 'Pattern catalog',
          description: 'Each pattern lives in core/ui/patterns and is composed from shared widgets.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in _patternCatalog)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.lgAll,
                      border: Border.all(color: colors.borderDefault),
                      color: colors.surfaceDefault,
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.$1,
                            style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                          ),
                          const SizedBox(height: AppSpacing.s1),
                          Text(
                            entry.$2,
                            style: typography.bodySm.copyWith(color: colors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.s1),
                          Text(
                            entry.$3,
                            style: typography.caption.copyWith(color: colors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        ShowcaseSection(
          id: 'pattern-state-gallery',
          title: 'State gallery',
          description: 'Loading, empty, error, access, degraded, and ready treatments.',
          child: StateGalleryPattern(
            state: _galleryState,
            onStateChanged: (state) => setState(() => _galleryState = state),
            config: const AppContentStateConfig(
              emptyFirstRunTitle: 'No services yet',
              emptyFirstRunDescription: 'Create your first billable service to appear in appointments and invoices.',
              emptyFirstRunActionLabel: 'Add service',
              emptyNoResultsTitle: 'No matching services',
              emptyNoResultsDescription: 'Try adjusting filters or search terms.',
              errorTitle: 'Could not load services',
              errorMessage: 'Check your connection and try again.',
              noAccessTitle: 'Services restricted',
              noAccessDescription: 'You do not have permission to view the service catalog.',
              degradedTitle: 'Showing cached services',
              degradedBody: 'Live updates are temporarily unavailable.',
            ),
            child: Center(
              child: Text(
                'Ready content preview',
                style: typography.body.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
