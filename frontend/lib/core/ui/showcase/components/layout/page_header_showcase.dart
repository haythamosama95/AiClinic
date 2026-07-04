import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class PageHeaderShowcase extends StatefulWidget {
  const PageHeaderShowcase({super.key});

  @override
  State<PageHeaderShowcase> createState() => _PageHeaderShowcaseState();
}

class _PageHeaderShowcaseState extends State<PageHeaderShowcase> {
  String _tab = 'overview';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ShowcaseSection(
      title: 'Page header',
      description: 'Title, description, breadcrumb, actions, and tabs slots.',
      child: ShowcaseDemo(
        label: 'Full composition',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: colors.borderDefault),
            color: colors.surfaceDefault,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s6),
            child: PageHeader(
              breadcrumb: AppBreadcrumb(
                items: const [
                  BreadcrumbItem(label: 'Billing', href: '#'),
                  BreadcrumbItem(label: 'Invoices', href: '#'),
                  BreadcrumbItem(label: 'INV-2026-00482'),
                ],
              ),
              title: 'Invoice details',
              description:
                  'Review line items, payments, and patient responsibility.',
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpacing.s2,
                children: [
                  AppButton(
                    onPressed: () {},
                    variant: AppButtonVariant.secondary,
                    child: const Text('Download PDF'),
                  ),
                  AppButton(
                    onPressed: () {},
                    child: const Text('Record payment'),
                  ),
                ],
              ),
              tabs: AppTabs(
                items: const [
                  TabItem(id: 'overview', label: Text('Overview')),
                  TabItem(id: 'payments', label: Text('Payments')),
                  TabItem(id: 'history', label: Text('History')),
                ],
                value: _tab,
                onChange: (id) => setState(() => _tab = id),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
