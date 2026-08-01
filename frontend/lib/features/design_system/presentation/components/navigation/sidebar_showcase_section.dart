import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/core/ui/components/app_sidebar.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';

/// App sidebar showcase (web `SidebarShowcase`).
class SidebarShowcaseSection extends ConsumerStatefulWidget {
  const SidebarShowcaseSection({super.key});

  @override
  ConsumerState<SidebarShowcaseSection> createState() => _SidebarShowcaseSectionState();
}

class _SidebarShowcaseSectionState extends ConsumerState<SidebarShowcaseSection> {
  var _activeId = 'patients';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'app-sidebar',
      title: 'App sidebar',
      description: 'Expanded and collapsed rail with Signal active indicator and keyboard navigation.',
      componentName: 'AppSidebar',
      child: ShowcaseDemoGrid(
        columns: 2,
        children: [
          ShowcaseDemo(
            label: 'Expanded',
            propsHint: 'collapsed={false}',
            child: _SidebarFrame(
              borderColor: colors.borderDefault,
              child: AppSidebar(
                items: clinicNavGroupsForShowcase(),
                footerItems: kClinicNavFooter,
                activeId: _activeId,
                onNavigate: (id) => setState(() => _activeId = id),
                collapsed: false,
                onToggleCollapsed: () {},
                org: kMockOrg,
                branch: kMockBranches.first.name,
              ),
            ),
          ),
          ShowcaseDemo(
            label: 'Collapsed rail',
            propsHint: 'collapsed={true}',
            child: _SidebarFrame(
              borderColor: colors.borderDefault,
              child: AppSidebar(
                items: clinicNavGroupsForShowcase(),
                footerItems: kClinicNavFooter,
                activeId: _activeId,
                onNavigate: (id) => setState(() => _activeId = id),
                collapsed: true,
                onToggleCollapsed: () {},
                org: kMockOrg,
                branch: kMockBranches.first.name,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarFrame extends StatelessWidget {
  const _SidebarFrame({required this.child, required this.borderColor});

  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 384,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: child,
        ),
      ),
    );
  }
}
