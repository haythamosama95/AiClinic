import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/components/navigation/branch_switcher_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/navigation/breadcrumb_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/navigation/command_bar_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/navigation/menu_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/navigation/pagination_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/navigation/sidebar_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/navigation/stepper_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/navigation/tabs_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/navigation/top_bar_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/navigation/user_menu_showcase.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Navigation component group — mirrors web `navigationSections`.
class NavigationShowcase extends StatelessWidget {
  const NavigationShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BreadcrumbShowcase(),
        SizedBox(height: AppSpacing.s16),
        TabsShowcase(),
        SizedBox(height: AppSpacing.s16),
        MenuShowcase(),
        SizedBox(height: AppSpacing.s16),
        PaginationShowcase(),
        SizedBox(height: AppSpacing.s16),
        StepperShowcase(),
        SizedBox(height: AppSpacing.s16),
        SidebarShowcase(),
        SizedBox(height: AppSpacing.s16),
        TopBarShowcase(),
        SizedBox(height: AppSpacing.s16),
        CommandBarShowcase(),
        SizedBox(height: AppSpacing.s16),
        BranchSwitcherShowcase(),
        SizedBox(height: AppSpacing.s16),
        UserMenuShowcase(),
      ],
    );
  }
}
