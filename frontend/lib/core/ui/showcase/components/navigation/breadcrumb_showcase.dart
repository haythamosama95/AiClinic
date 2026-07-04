import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class BreadcrumbShowcase extends StatelessWidget {
  const BreadcrumbShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection(
      title: 'Breadcrumb',
      description:
          'Hierarchical wayfinding. The current page is not a link.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.s4,
        children: const [
          ShowcaseDemo(
            label: 'Default trail',
            child: AppBreadcrumb(
              items: [
                BreadcrumbItem(label: 'Home', href: '#'),
                BreadcrumbItem(label: 'Patients', href: '#'),
                BreadcrumbItem(label: 'Layla Hassan'),
              ],
            ),
          ),
          ShowcaseDemo(
            label: 'Long trail (middle truncates on narrow)',
            child: AppBreadcrumb(
              items: [
                BreadcrumbItem(label: 'Home', href: '#'),
                BreadcrumbItem(label: 'Billing', href: '#'),
                BreadcrumbItem(label: 'Invoices', href: '#'),
                BreadcrumbItem(label: 'INV-2026-00482'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
