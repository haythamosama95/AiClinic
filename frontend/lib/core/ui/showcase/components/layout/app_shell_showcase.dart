import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class AppShellShowcase extends ConsumerStatefulWidget {
  const AppShellShowcase({super.key});

  @override
  ConsumerState<AppShellShowcase> createState() => _AppShellShowcaseState();
}

class _AppShellShowcaseState extends ConsumerState<AppShellShowcase> {
  String _activeId = 'patients';
  bool _collapsed = false;
  String _branchId = mockBranches.first.id;
  String _tab = 'overview';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final branch = mockBranches.firstWhere(
      (b) => b.id == _branchId,
      orElse: () => mockBranches.first,
    );

    return ShowcaseSection(
      title: 'App shell',
      description:
          'Live shell with sidebar, top bar, command bar, and placeholder page content.',
      child: ShowcaseDemo(
        label: 'Live shell demo',
        child: SizedBox(
          height: 512,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppRadius.xlAll,
              border: Border.all(color: colors.borderDefault),
              boxShadow: context.elevation.level2,
            ),
            child: ClipRRect(
              borderRadius: AppRadius.xlAll,
              child: AppShell(
                sidebar: AppSidebar(
                  items: clinicNavGroups,
                  footerItems: clinicNavFooter,
                  activeId: _activeId,
                  onNavigate: (id) => setState(() => _activeId = id),
                  collapsed: _collapsed,
                  onToggleCollapsed: () => setState(() => _collapsed = !_collapsed),
                  org: mockOrg,
                  branch: branch.name,
                ),
                topBar: AppTopBar(
                  pageContext: AppBreadcrumb(
                    items: [
                      BreadcrumbItem(
                        label: 'Patients',
                        onTap: () => setState(() => _activeId = 'patients'),
                      ),
                      const BreadcrumbItem(label: 'Directory'),
                    ],
                  ),
                  branches: mockBranches,
                  currentBranchId: _branchId,
                  onBranchChange: (id) => setState(() => _branchId = id),
                  user: mockUser,
                  notificationCount: mockNotificationCount,
                  onCommandBarOpen: () =>
                      ref.read(commandBarProvider.notifier).openCommandBar(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PageHeader(
                      title: 'Patients',
                      description:
                          'Manage patient records, demographics, and care history.',
                      actions: AppButton(
                        onPressed: () {},
                        child: const Text('New patient'),
                      ),
                      tabs: AppTabs(
                        items: const [
                          TabItem(id: 'overview', label: Text('Overview')),
                          TabItem(id: 'active', label: Text('Active')),
                          TabItem(id: 'archived', label: Text('Archived')),
                        ],
                        value: _tab,
                        onChange: (id) => setState(() => _tab = id),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final crossCount = constraints.maxWidth > 640 ? 3 : 1;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: AppSpacing.s4,
                          children: [
                            GridView.count(
                              crossAxisCount: crossCount,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: AppSpacing.s4,
                              crossAxisSpacing: AppSpacing.s4,
                              childAspectRatio: 2.4,
                              children: List.generate(
                                3,
                                (_) => const AppSkeleton(height: 96),
                              ),
                            ),
                            const AppSkeleton(height: 192),
                            const AppSkeleton(height: 128),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
