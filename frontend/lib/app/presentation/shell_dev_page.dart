import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/shell_nav.dart';
import 'package:ai_clinic/core/ui/layout/page_header.dart';
import 'package:ai_clinic/core/ui/navigation/tabs.dart';
import 'package:ai_clinic/core/ui/showcase/components_showcase.dart';
import 'package:ai_clinic/core/ui/showcase/design_system_showcase_page.dart';
import 'package:ai_clinic/core/ui/showcase/dev_locale_controls.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';

/// In-shell design system route — mirrors web `DevPage`.
class ShellDevPage extends StatelessWidget {
  const ShellDevPage({required this.section, super.key});

  final ShellDevSection section;

  @override
  Widget build(BuildContext context) {
    final meta = shellMetaForNavId('dev');
    final tabId = section == ShellDevSection.foundations
        ? 'foundations'
        : 'components';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: meta.title,
          description: meta.description,
          tabs: AppTabs(
            items: const [
              TabItem(id: 'foundations', label: Text('Foundations')),
              TabItem(id: 'components', label: Text('Components')),
            ],
            value: tabId,
            onChange: (id) => context.go(
              id == 'foundations'
                  ? AppRoutes.devFoundations
                  : AppRoutes.devComponents,
            ),
            ariaLabel: 'Design system sections',
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        const DevLocaleControls(),
        const SizedBox(height: AppSpacing.s8),
        if (section == ShellDevSection.foundations)
          const DesignSystemShowcasePage(embedded: true)
        else
          const ComponentsShowcase(),
      ],
    );
  }
}
