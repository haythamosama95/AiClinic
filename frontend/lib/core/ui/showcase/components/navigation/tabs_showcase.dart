import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class TabsShowcase extends StatefulWidget {
  const TabsShowcase({super.key});

  @override
  State<TabsShowcase> createState() => _TabsShowcaseState();
}

class _TabsShowcaseState extends State<TabsShowcase> {
  String _underline = 'overview';
  String _segmented = 'overview';
  String _vertical = 'overview';

  static const _tabItems = [
    TabItem(id: 'overview', label: Text('Overview')),
    TabItem(id: 'visits', label: Text('Visits')),
    TabItem(id: 'billing', label: Text('Billing')),
    TabItem(id: 'documents', label: Text('Documents'), disabled: true),
  ];

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection(
      title: 'Tabs',
      description:
          'Underline (Signal), segmented, and vertical variants with arrow-key navigation.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.s4,
        children: [
          ShowcaseDemo(
            label: 'Underline (default)',
            child: AppTabs(
              items: _tabItems,
              value: _underline,
              onChange: (id) => setState(() => _underline = id),
            ),
          ),
          ShowcaseDemo(
            label: 'Segmented',
            child: AppTabs(
              items: _tabItems.where((t) => !t.disabled).toList(),
              value: _segmented,
              onChange: (id) => setState(() => _segmented = id),
              variant: AppTabsVariant.segmented,
            ),
          ),
          ShowcaseDemo(
            label: 'Vertical',
            child: SizedBox(
              width: 192,
              child: AppTabs(
                items: _tabItems,
                value: _vertical,
                onChange: (id) => setState(() => _vertical = id),
                variant: AppTabsVariant.vertical,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
