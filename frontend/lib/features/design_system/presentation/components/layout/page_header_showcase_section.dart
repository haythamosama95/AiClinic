import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_breadcrumb.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/components/app_tabs.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _PageHeaderCopy {
  const _PageHeaderCopy({
    required this.sectionDescription,
    required this.fullComposition,
    required this.fullCompositionHint,
    required this.billing,
    required this.invoices,
    required this.invoiceId,
    required this.title,
    required this.description,
    required this.downloadPdf,
    required this.recordPayment,
    required this.overview,
    required this.payments,
    required this.history,
  });

  final String sectionDescription;
  final String fullComposition;
  final String fullCompositionHint;
  final String billing;
  final String invoices;
  final String invoiceId;
  final String title;
  final String description;
  final String downloadPdf;
  final String recordPayment;
  final String overview;
  final String payments;
  final String history;
}

const _copyEn = _PageHeaderCopy(
  sectionDescription: 'Title, description, breadcrumb, actions, and tabs slots.',
  fullComposition: 'Full composition',
  fullCompositionHint: 'title + breadcrumb + actions + tabs',
  billing: 'Billing',
  invoices: 'Invoices',
  invoiceId: 'INV-2026-00482',
  title: 'Invoice details',
  description: 'Review line items, payments, and patient responsibility.',
  downloadPdf: 'Download PDF',
  recordPayment: 'Record payment',
  overview: 'Overview',
  payments: 'Payments',
  history: 'History',
);

const _copyAr = _PageHeaderCopy(
  sectionDescription: 'عنوان ووصف ومسار تنقل وإجراءات وتبويبات.',
  fullComposition: 'تركيبة كاملة',
  fullCompositionHint: 'title + breadcrumb + actions + tabs',
  billing: 'الفوترة',
  invoices: 'الفواتير',
  invoiceId: 'INV-2026-00482',
  title: 'تفاصيل الفاتورة',
  description: 'راجع البنود والمدفوعات ومسؤولية المريض.',
  downloadPdf: 'تنزيل PDF',
  recordPayment: 'تسجيل دفعة',
  overview: 'نظرة عامة',
  payments: 'المدفوعات',
  history: 'السجل',
);

_PageHeaderCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Page header showcase (web `PageHeaderShowcase`).
class PageHeaderShowcaseSection extends ConsumerStatefulWidget {
  const PageHeaderShowcaseSection({super.key});

  @override
  ConsumerState<PageHeaderShowcaseSection> createState() => _PageHeaderShowcaseSectionState();
}

class _PageHeaderShowcaseSectionState extends ConsumerState<PageHeaderShowcaseSection> {
  var _tab = 'overview';

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'page-header',
      title: 'Page header',
      description: copy.sectionDescription,
      componentName: 'PageHeader',
      child: ShowcaseDemo(
        label: copy.fullComposition,
        propsHint: copy.fullCompositionHint,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceDefault,
            border: Border.all(color: colors.borderDefault),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space6),
            child: AppPageHeader(
              breadcrumb: AppBreadcrumb(
                items: [
                  AppBreadcrumbItem(label: copy.billing, href: '#'),
                  AppBreadcrumbItem(label: copy.invoices, href: '#'),
                  AppBreadcrumbItem(label: copy.invoiceId),
                ],
              ),
              title: copy.title,
              description: copy.description,
              actions: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpacing.space2,
                children: [
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    onPressed: () {},
                    child: Text(copy.downloadPdf),
                  ),
                  AppButton(
                    variant: AppButtonVariant.primary,
                    onPressed: () {},
                    child: Text(copy.recordPayment),
                  ),
                ],
              ),
              tabs: AppTabs(
                items: [
                  AppTabItem(id: 'overview', label: copy.overview),
                  AppTabItem(id: 'payments', label: copy.payments),
                  AppTabItem(id: 'history', label: copy.history),
                ],
                value: _tab,
                onChanged: (id) => setState(() => _tab = id),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
