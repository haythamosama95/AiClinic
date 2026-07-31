import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_breadcrumb.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/core/ui/components/app_top_bar.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';

/// App top bar showcase (web `TopBarShowcase`).
class TopBarShowcaseSection extends ConsumerStatefulWidget {
  const TopBarShowcaseSection({super.key});

  @override
  ConsumerState<TopBarShowcaseSection> createState() => _TopBarShowcaseSectionState();
}

class _TopBarShowcaseSectionState extends ConsumerState<TopBarShowcaseSection> {
  var _branchId = kMockBranches.first.id;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'app-topbar',
      title: 'App top bar',
      description: 'Sticky chrome with command trigger, branch switcher, notifications, theme toggle, and user menu.',
      componentName: 'AppTopBar',
      child: ShowcaseDemo(
        label: 'Default composition',
        propsHint: 'slots + live providers',
        child: SizedBox(
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.borderDefault),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: AppTopBar(
                pageContext: const AppBreadcrumb(
                  items: [
                    AppBreadcrumbItem(label: 'Patients', href: '#'),
                    AppBreadcrumbItem(label: 'Layla Hassan'),
                  ],
                ),
                branches: kMockBranches,
                currentBranchId: _branchId,
                onBranchChange: (id) => setState(() => _branchId = id),
                user: kMockUser,
                notificationCount: kMockNotificationCount(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
