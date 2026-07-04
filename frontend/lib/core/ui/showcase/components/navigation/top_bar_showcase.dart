import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class TopBarShowcase extends StatefulWidget {
  const TopBarShowcase({super.key});

  @override
  State<TopBarShowcase> createState() => _TopBarShowcaseState();
}

class _TopBarShowcaseState extends State<TopBarShowcase> {
  String _branchId = mockBranches.first.id;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ShowcaseSection(
      title: 'App top bar',
      description:
          'Sticky chrome with command trigger, branch switcher, AI toggle, and user menu.',
      child: ShowcaseDemo(
        label: 'Default composition',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: colors.borderDefault),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.lgAll,
            child: AppTopBar(
              pageContext: const AppBreadcrumb(
                items: [
                  BreadcrumbItem(label: 'Patients', href: '#'),
                  BreadcrumbItem(label: 'Layla Hassan'),
                ],
              ),
              branches: mockBranches,
              currentBranchId: _branchId,
              onBranchChange: (id) => setState(() => _branchId = id),
              user: mockUser,
              notificationCount: mockNotificationCount,
            ),
          ),
        ),
      ),
    );
  }
}
