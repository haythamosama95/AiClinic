import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_tabs.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';

const _tabItems = <AppTabItem>[
  AppTabItem(id: 'overview', label: 'Overview'),
  AppTabItem(id: 'visits', label: 'Visits'),
  AppTabItem(id: 'billing', label: 'Billing'),
  AppTabItem(id: 'documents', label: 'Documents', disabled: true),
];

/// Tabs component showcase (web `TabsShowcase`).
class TabsShowcaseSection extends ConsumerStatefulWidget {
  const TabsShowcaseSection({super.key});

  @override
  ConsumerState<TabsShowcaseSection> createState() => _TabsShowcaseSectionState();
}

class _TabsShowcaseSectionState extends ConsumerState<TabsShowcaseSection> {
  var _underline = 'overview';
  var _segmented = 'overview';
  var _vertical = 'overview';

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection(
      id: 'tabs',
      title: 'Tabs',
      description: 'Underline (Signal), segmented, and vertical variants with arrow-key navigation.',
      componentName: 'Tabs',
      child: ShowcaseDemoGrid(
        columns: 1,
        children: [
          ShowcaseDemo(
            label: 'Underline (default)',
            propsHint: 'variant="underline"',
            child: AppTabs(
              items: _tabItems,
              value: _underline,
              onChanged: (id) => setState(() => _underline = id),
            ),
          ),
          ShowcaseDemo(
            label: 'Segmented',
            propsHint: 'variant="segmented"',
            child: AppTabs(
              items: _tabItems.where((item) => !item.disabled).toList(),
              value: _segmented,
              onChanged: (id) => setState(() => _segmented = id),
              variant: AppTabsVariant.segmented,
            ),
          ),
          ShowcaseDemo(
            label: 'Vertical',
            propsHint: 'variant="vertical"',
            child: SizedBox(
              width: 192,
              child: AppTabs(
                items: _tabItems,
                value: _vertical,
                onChanged: (id) => setState(() => _vertical = id),
                variant: AppTabsVariant.vertical,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
