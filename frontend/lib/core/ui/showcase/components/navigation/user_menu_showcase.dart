import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class UserMenuShowcase extends StatelessWidget {
  const UserMenuShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection(
      title: 'User menu',
      description: 'Avatar trigger with profile, theme, language, and sign out.',
      child: ShowcaseDemo(
        label: 'Default',
        child: UserMenu(user: mockUser, appVersion: '0.1.0'),
      ),
    );
  }
}
