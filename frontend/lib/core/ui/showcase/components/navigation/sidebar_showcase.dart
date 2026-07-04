import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class SidebarShowcase extends StatefulWidget {
  const SidebarShowcase({super.key});

  @override
  State<SidebarShowcase> createState() => _SidebarShowcaseState();
}

class _SidebarShowcaseState extends State<SidebarShowcase> {
  String _activeId = 'patients';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget sidebarDemo({required bool collapsed}) {
      return SizedBox(
        height: 384,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: colors.borderDefault),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.lgAll,
            child: AppSidebar(
              items: clinicNavGroups,
              footerItems: clinicNavFooter,
              activeId: _activeId,
              onNavigate: (id) => setState(() => _activeId = id),
              collapsed: collapsed,
              onToggleCollapsed: () {},
              org: mockOrg,
              branch: mockBranches.first.name,
            ),
          ),
        ),
      );
    }

    return ShowcaseSection(
      title: 'App sidebar',
      description:
          'Expanded and collapsed rail with Signal active indicator and keyboard navigation.',
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: 'Expanded',
            child: sidebarDemo(collapsed: false),
          ),
          ShowcaseDemo(
            label: 'Collapsed rail',
            child: sidebarDemo(collapsed: true),
          ),
        ],
      ),
    );
  }
}
