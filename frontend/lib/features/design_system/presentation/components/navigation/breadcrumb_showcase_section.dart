import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_breadcrumb.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _BreadcrumbCopy {
  const _BreadcrumbCopy({
    required this.description,
    required this.defaultTrail,
    required this.defaultTrailHint,
    required this.longTrail,
    required this.longTrailHint,
    required this.home,
    required this.patients,
    required this.patientName,
    required this.billing,
    required this.invoices,
    required this.invoiceId,
  });

  final String description;
  final String defaultTrail;
  final String defaultTrailHint;
  final String longTrail;
  final String longTrailHint;
  final String home;
  final String patients;
  final String patientName;
  final String billing;
  final String invoices;
  final String invoiceId;
}

const _copyEn = _BreadcrumbCopy(
  description: 'Hierarchical wayfinding. The current page is not a link.',
  defaultTrail: 'Default trail',
  defaultTrailHint: 'items with href',
  longTrail: 'Long trail (middle truncates on narrow)',
  longTrailHint: 'overflow',
  home: 'Home',
  patients: 'Patients',
  patientName: 'Layla Hassan',
  billing: 'Billing',
  invoices: 'Invoices',
  invoiceId: 'INV-2026-00482',
);

const _copyAr = _BreadcrumbCopy(
  description: 'توجيه هرمي. الصفحة الحالية ليست رابطًا.',
  defaultTrail: 'مسار افتراضي',
  defaultTrailHint: 'items with href',
  longTrail: 'مسار طويل (يُختصر في المنتصف عند الضيق)',
  longTrailHint: 'overflow',
  home: 'الرئيسية',
  patients: 'المرضى',
  patientName: 'ليلى حسن',
  billing: 'الفوترة',
  invoices: 'الفواتير',
  invoiceId: 'INV-2026-00482',
);

_BreadcrumbCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Breadcrumb showcase (web `BreadcrumbShowcase`).
class BreadcrumbShowcaseSection extends ConsumerWidget {
  const BreadcrumbShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'breadcrumb',
      title: 'Breadcrumb',
      description: copy.description,
      componentName: 'Breadcrumb',
      child: ShowcaseDemoGrid(
        columns: 1,
        children: [
          ShowcaseDemo(
            label: copy.defaultTrail,
            propsHint: copy.defaultTrailHint,
            child: AppBreadcrumb(
              items: [
                AppBreadcrumbItem(label: copy.home, href: '#'),
                AppBreadcrumbItem(label: copy.patients, href: '#'),
                AppBreadcrumbItem(label: copy.patientName),
              ],
            ),
          ),
          ShowcaseDemo(
            label: copy.longTrail,
            propsHint: copy.longTrailHint,
            child: AppBreadcrumb(
              items: [
                AppBreadcrumbItem(label: copy.home, href: '#'),
                AppBreadcrumbItem(label: copy.billing, href: '#'),
                AppBreadcrumbItem(label: copy.invoices, href: '#'),
                AppBreadcrumbItem(label: copy.invoiceId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
