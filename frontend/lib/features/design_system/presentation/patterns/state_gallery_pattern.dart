import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_alert.dart';
import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_error_state.dart';
import 'package:ai_clinic/core/ui/components/app_loading_overlay.dart';
import 'package:ai_clinic/core/ui/components/app_segmented_control.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/patterns/pattern_frame.dart';
import 'package:ai_clinic/features/design_system/presentation/patterns/pattern_mock_data.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/showcase_primitives.dart';

/// State gallery pattern (web `StateGalleryPattern`).
class StateGalleryPattern extends StatefulWidget {
  const StateGalleryPattern({super.key});

  @override
  State<StateGalleryPattern> createState() => _StateGalleryPatternState();
}

class _StateGalleryPatternState extends State<StateGalleryPattern> {
  var _state = 'ready';

  static const _stateOptions = <String, String>{
    'loading': 'Loading',
    'empty-first': 'First-run',
    'empty-results': 'No results',
    'error': 'Error',
    'no-access': 'No access',
    'degraded': 'Degraded',
    'ready': 'Ready',
  };

  @override
  Widget build(BuildContext context) {
    final columns = <TableColumn<PatternServiceRow>>[
      TableColumn(id: 'name', header: 'Service', accessor: (row) => Text(row.name)),
      TableColumn(
        id: 'price',
        header: 'Price',
        align: TableAlign.end,
        accessor: (row) => Text(row.defaultPrice.toStringAsFixed(2)),
      ),
    ];

    return ShowcaseSection(
      id: 'pattern-state-gallery',
      title: 'State gallery',
      componentName: '05 §6 Content states',
      description: 'Loading, empty, error, no-access, and degraded treatments on a representative list surface.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSegmentedControl<String>(
            ariaLabel: 'Preview content state',
            size: AppSegmentedControlSize.sm,
            value: _state,
            onChanged: (value) => setState(() => _state = value),
            options: [
              for (final entry in _stateOptions.entries) SegmentedOption(value: entry.key, label: Text(entry.value)),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          PatternFrame(
            minHeight: 320,
            child: Stack(
              children: [
                if (_state == 'degraded')
                  const AppAlert(
                    variant: AppAlertVariant.warning,
                    title: 'Read-only mode',
                    child: Text('Your subscription limits edits. You can still view all records.'),
                  ),
                if (_state == 'loading')
                  AppLoadingOverlay(
                    scoped: true,
                    label: 'Loading services…',
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppSkeleton(variant: SkeletonVariant.rectangular, width: 192, height: 32),
                          const SizedBox(height: AppSpacing.space3),
                          const AppSkeleton(variant: SkeletonVariant.rectangular, height: 40),
                          for (var i = 0; i < 4; i++) ...[
                            const SizedBox(height: AppSpacing.space3),
                            const AppSkeleton(variant: SkeletonVariant.rectangular, height: 40),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (_state == 'empty-first')
                  AppEmptyState(
                    variant: AppEmptyStateVariant.firstRun,
                    title: 'No services yet',
                    description: 'Add your first service to start billing.',
                    action: EmptyStateAction(label: 'Add service', onPressed: () {}),
                  ),
                if (_state == 'empty-results')
                  AppEmptyState(
                    variant: AppEmptyStateVariant.noResults,
                    title: 'No matches',
                    description: 'Try adjusting your search or filters.',
                    action: EmptyStateAction(label: 'Clear filters', onPressed: () {}),
                  ),
                if (_state == 'error')
                  AppErrorState(
                    message: "Can't reach the server. Check your connection and try again.",
                    onRetry: () {},
                  ),
                if (_state == 'no-access')
                  const AppEmptyState(
                    variant: AppEmptyStateVariant.noAccess,
                    title: 'No access',
                    description: 'You need the services.view permission to see this catalog.',
                  ),
                if (_state == 'ready' || _state == 'degraded')
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: AppDataTable<PatternServiceRow>(
                      columns: columns,
                      data: kPatternMockServices.take(5).toList(),
                      getRowId: (row) => row.id,
                      ariaLabel: 'Services preview',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
