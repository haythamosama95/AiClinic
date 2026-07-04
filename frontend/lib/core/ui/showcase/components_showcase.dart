import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/components/actions_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/display_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/inputs_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/layout/layout_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/components/navigation/navigation_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Components tab content mirroring the web ComponentsPage groups.
class ComponentsShowcase extends StatelessWidget {
  const ComponentsShowcase({super.key});

  static const _groups = [
    (
      'Actions',
      'Buttons, icon buttons, segmented controls, and split actions.',
      ActionsShowcase(),
    ),
    (
      'Display',
      'Avatars, badges, chips, progress, skeletons, and tooltips.',
      DisplayShowcase(),
    ),
    (
      'Inputs',
      'Text fields, selects, choice controls, date/time, and file upload.',
      InputsShowcase(),
    ),
    (
      'Navigation',
      'Sidebar, tabs, menus, Command Bar, and wayfinding.',
      NavigationShowcase(),
    ),
    (
      'Layout',
      'Headers, toolbars, scroll areas, and shell composition.',
      LayoutShowcase(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Shared primitives with full variant and state matrices. '
          'Use Preview theming above for density, direction, and locale.',
          style: typography.bodyLg.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s10),
        for (final (title, description, child) in _groups) ...[
          ShowcaseGroupHeader(title: title, description: description),
          const SizedBox(height: AppSpacing.s6),
          child,
          const SizedBox(height: AppSpacing.s16),
        ],
      ],
    );
  }
}
