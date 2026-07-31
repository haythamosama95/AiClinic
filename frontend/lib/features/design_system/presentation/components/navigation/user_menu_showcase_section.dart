import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/core/ui/components/app_user_menu.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';

/// User menu showcase (web `UserMenuShowcase`).
class UserMenuShowcaseSection extends StatelessWidget {
  const UserMenuShowcaseSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const ShowcaseSection(
      id: 'user-menu',
      title: 'User menu',
      description: 'Avatar trigger with profile, theme, language, and sign out.',
      componentName: 'UserMenu',
      child: ShowcaseDemo(
        label: 'Default',
        propsHint: 'user + appVersion',
        child: AppUserMenu(user: kMockUser, appVersion: '0.1.0'),
      ),
    );
  }
}
