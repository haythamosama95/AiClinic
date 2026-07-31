import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_segmented_control.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

const _copy = {
  'en': {
    'list': 'List',
    'board': 'Board',
    'day': 'Day',
    'week': 'Week',
    'viewMode': 'View mode',
    'scheduleView': 'Schedule view',
  },
  'ar': {
    'list': 'قائمة',
    'board': 'لوحة',
    'day': 'يوم',
    'week': 'أسبوع',
    'viewMode': 'وضع العرض',
    'scheduleView': 'عرض الجدول',
  },
};

/// Segmented control showcase section (web `SegmentedControlShowcase`).
class SegmentedControlShowcaseSection extends ConsumerStatefulWidget {
  const SegmentedControlShowcaseSection({super.key});

  @override
  ConsumerState<SegmentedControlShowcaseSection> createState() => _SegmentedControlShowcaseSectionState();
}

class _SegmentedControlShowcaseSectionState extends ConsumerState<SegmentedControlShowcaseSection> {
  String _viewMode = 'list';
  String _scheduleView = 'day';

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(devPreviewProvider).locale;
    final t = _copy[locale] ?? _copy['en']!;

    return ShowcaseSection(
      id: 'segmented-control',
      title: 'Button group / Segmented control',
      description: 'Mutually exclusive choice among 2–5 options. role="radiogroup" with arrow-key navigation.',
      componentName: 'AppSegmentedControl',
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: 'View mode',
            propsHint: 'with icons',
            child: AppSegmentedControl<String>(
              ariaLabel: t['viewMode']!,
              value: _viewMode,
              onChanged: (value) => setState(() => _viewMode = value),
              options: [
                SegmentedOption(
                  value: 'list',
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.view_list, size: 14),
                      const SizedBox(width: 6),
                      Text(t['list']!),
                    ],
                  ),
                ),
                SegmentedOption(
                  value: 'board',
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.grid_view, size: 14),
                      const SizedBox(width: 6),
                      Text(t['board']!),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ShowcaseDemo(
            label: 'Size sm',
            propsHint: 'size="sm"',
            child: AppSegmentedControl<String>(
              size: AppSegmentedControlSize.sm,
              ariaLabel: t['scheduleView']!,
              value: _scheduleView,
              onChanged: (value) => setState(() => _scheduleView = value),
              options: [
                SegmentedOption(value: 'day', label: Text(t['day']!)),
                SegmentedOption(value: 'week', label: Text(t['week']!)),
              ],
            ),
          ),
          ShowcaseDemo(
            label: 'With disabled option',
            child: AppSegmentedControl<String>(
              ariaLabel: t['viewMode']!,
              value: 'list',
              onChanged: (_) {},
              options: [
                SegmentedOption(value: 'list', label: Text(t['list']!)),
                SegmentedOption(value: 'board', label: Text(t['board']!), disabled: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
