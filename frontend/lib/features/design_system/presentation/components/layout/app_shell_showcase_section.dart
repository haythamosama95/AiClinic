import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/shell/layout/app_shell.dart';
import 'package:ai_clinic/core/ui/components/app_breadcrumb.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_command_bar.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/core/ui/components/app_sidebar.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/core/ui/components/app_tabs.dart';
import 'package:ai_clinic/core/ui/components/app_top_bar.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';

/// App shell showcase (web `AppShellShowcase`).
class AppShellShowcaseSection extends ConsumerStatefulWidget {
  const AppShellShowcaseSection({super.key});

  @override
  ConsumerState<AppShellShowcaseSection> createState() => _AppShellShowcaseSectionState();
}

class _AppShellShowcaseSectionState extends ConsumerState<AppShellShowcaseSection> {
  var _activeId = 'patients';
  var _collapsed = false;
  var _branchId = kMockBranches.first.id;
  var _tab = 'overview';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final branch = kMockBranches.firstWhere((item) => item.id == _branchId, orElse: () => kMockBranches.first);

    return ShowcaseSection(
      id: 'app-shell',
      title: 'App shell',
      description: 'Live shell with sidebar, top bar, command bar, and placeholder page content.',
      componentName: 'AppShell',
      child: ShowcaseDemo(
        label: 'Live shell demo',
        propsHint: '⌘K · collapse · toggles',
        child: SizedBox(
          height: 512,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.borderDefault),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: CommandBarScope(
                items: kDefaultCommandItems(onNavigate: (id) => setState(() => _activeId = id)),
                child: AppShell(
                  fillViewport: true,
                  sidebar: AppSidebar(
                    items: clinicNavGroupsForShowcase(),
                    footerItems: kClinicNavFooter,
                    activeId: _activeId,
                    onNavigate: (id) => setState(() => _activeId = id),
                    collapsed: _collapsed,
                    onToggleCollapsed: () => setState(() => _collapsed = !_collapsed),
                    org: kMockOrg,
                    branch: branch.name,
                  ),
                  topBar: AppTopBar(
                    pageContext: AppBreadcrumb(
                      items: [
                        AppBreadcrumbItem(label: 'Patients', onTap: () => setState(() => _activeId = 'patients')),
                        const AppBreadcrumbItem(label: 'Directory'),
                      ],
                    ),
                    branches: kMockBranches,
                    currentBranchId: _branchId,
                    onBranchChange: (id) => setState(() => _branchId = id),
                    user: kMockUser,
                    notificationCount: kMockNotificationCount(),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Patients', style: AppTypography.h2(context)),
                                  const SizedBox(height: AppSpacing.space1),
                                  Text(
                                    'Manage patient records, demographics, and care history.',
                                    style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const AppButton(variant: AppButtonVariant.primary, child: Text('New patient')),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.space6),
                        AppTabs(
                          variant: AppTabsVariant.underline,
                          items: const [
                            AppTabItem(id: 'overview', label: 'Overview'),
                            AppTabItem(id: 'active', label: 'Active'),
                            AppTabItem(id: 'archived', label: 'Archived'),
                          ],
                          value: _tab,
                          onChanged: (id) => setState(() => _tab = id),
                        ),
                        const SizedBox(height: AppSpacing.space8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final cardWidth = constraints.maxWidth >= 640
                                ? (constraints.maxWidth - AppSpacing.space4 * 2) / 3
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: AppSpacing.space4,
                              runSpacing: AppSpacing.space4,
                              children: [
                                for (var index = 0; index < 3; index++)
                                  SizedBox(
                                    width: cardWidth,
                                    child: const AppSkeleton(variant: SkeletonVariant.rectangular, height: 96),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.space4),
                        const AppSkeleton(variant: SkeletonVariant.rectangular, height: 192),
                        const SizedBox(height: AppSpacing.space4),
                        const AppSkeleton(variant: SkeletonVariant.rectangular, height: 128),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
