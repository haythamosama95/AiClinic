import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/components/layout/app_shell_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/layout/page_header_showcase.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Layout component group — mirrors web `layoutSections`.
class LayoutShowcase extends StatelessWidget {
  const LayoutShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppShellShowcase(),
        SizedBox(height: AppSpacing.s16),
        PageHeaderShowcase(),
      ],
    );
  }
}
