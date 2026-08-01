import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

const _variants = <BadgeVariant>[
  BadgeVariant.solid,
  BadgeVariant.soft,
  BadgeVariant.outline,
  BadgeVariant.dot,
];

const _colors = <BadgeColor>[
  BadgeColor.neutral,
  BadgeColor.success,
  BadgeColor.warning,
  BadgeColor.danger,
  BadgeColor.info,
  BadgeColor.teal,
  BadgeColor.ai,
];

const _sizes = <BadgeSize>[BadgeSize.sm, BadgeSize.md];

class _DomainStatus {
  const _DomainStatus({required this.labelKey, required this.color});

  final String labelKey;
  final BadgeColor color;
}

const _domainStatuses = <_DomainStatus>[
  _DomainStatus(labelKey: 'paid', color: BadgeColor.success),
  _DomainStatus(labelKey: 'active', color: BadgeColor.success),
  _DomainStatus(labelKey: 'confirmed', color: BadgeColor.success),
  _DomainStatus(labelKey: 'pending', color: BadgeColor.warning),
  _DomainStatus(labelKey: 'draft', color: BadgeColor.neutral),
  _DomainStatus(labelKey: 'overdue', color: BadgeColor.danger),
  _DomainStatus(labelKey: 'cancelled', color: BadgeColor.danger),
  _DomainStatus(labelKey: 'inProgress', color: BadgeColor.info),
  _DomainStatus(labelKey: 'aiSuggested', color: BadgeColor.ai),
];

class _BadgeCopy {
  const _BadgeCopy({
    required this.sectionDescription,
    required this.statusColors,
    required this.sizes,
    required this.domainStatusMapping,
    required this.dotAccessibleLabel,
    required this.variantSolid,
    required this.variantSoft,
    required this.variantOutline,
    required this.variantDot,
    required this.paid,
    required this.active,
    required this.confirmed,
    required this.pending,
    required this.draft,
    required this.overdue,
    required this.cancelled,
    required this.inProgress,
    required this.aiSuggested,
    required this.noShow,
  });

  final String sectionDescription;
  final String statusColors;
  final String sizes;
  final String domainStatusMapping;
  final String dotAccessibleLabel;
  final String variantSolid;
  final String variantSoft;
  final String variantOutline;
  final String variantDot;
  final String paid;
  final String active;
  final String confirmed;
  final String pending;
  final String draft;
  final String overdue;
  final String cancelled;
  final String inProgress;
  final String aiSuggested;
  final String noShow;

  String variantLabel(BadgeVariant variant) => switch (variant) {
    BadgeVariant.solid => variantSolid,
    BadgeVariant.soft => variantSoft,
    BadgeVariant.outline => variantOutline,
    BadgeVariant.dot => variantDot,
  };
}

const _copyEn = _BadgeCopy(
  sectionDescription:
      'Status and counts. Always paired with text; dot-only badges need an accessible label.',
  statusColors: 'Status colors',
  sizes: 'Sizes',
  domainStatusMapping: 'Domain status mapping',
  dotAccessibleLabel: 'Dot with accessible label',
  variantSolid: 'Variant · solid',
  variantSoft: 'Variant · soft',
  variantOutline: 'Variant · outline',
  variantDot: 'Variant · dot',
  paid: 'Paid',
  active: 'Active',
  confirmed: 'Confirmed',
  pending: 'Pending',
  draft: 'Draft',
  overdue: 'Overdue',
  cancelled: 'Cancelled',
  inProgress: 'In progress',
  aiSuggested: 'AI suggested',
  noShow: 'No-show',
);

const _copyAr = _BadgeCopy(
  sectionDescription:
      'حالات وأعداد. تُعرض دائمًا مع نص؛ الشارات النقطية فقط تحتاج تسمية يمكن الوصول إليها.',
  statusColors: 'ألوان الحالة',
  sizes: 'الأحجام',
  domainStatusMapping: 'تعيين حالات النطاق',
  dotAccessibleLabel: 'نقطة مع تسمية يمكن الوصول إليها',
  variantSolid: 'المتغير · solid',
  variantSoft: 'المتغير · soft',
  variantOutline: 'المتغير · outline',
  variantDot: 'المتغير · dot',
  paid: 'مدفوع',
  active: 'نشط',
  confirmed: 'مؤكد',
  pending: 'قيد الانتظار',
  draft: 'مسودة',
  overdue: 'متأخر',
  cancelled: 'ملغى',
  inProgress: 'قيد التنفيذ',
  aiSuggested: 'مقترح بالذكاء الاصطناعي',
  noShow: 'لم يحضر',
);

_BadgeCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

String _domainLabel(_BadgeCopy copy, String labelKey) => switch (labelKey) {
  'paid' => copy.paid,
  'active' => copy.active,
  'confirmed' => copy.confirmed,
  'pending' => copy.pending,
  'draft' => copy.draft,
  'overdue' => copy.overdue,
  'cancelled' => copy.cancelled,
  'inProgress' => copy.inProgress,
  'aiSuggested' => copy.aiSuggested,
  _ => labelKey,
};

String _colorName(BadgeColor color) => switch (color) {
  BadgeColor.neutral => 'neutral',
  BadgeColor.success => 'success',
  BadgeColor.warning => 'warning',
  BadgeColor.danger => 'danger',
  BadgeColor.info => 'info',
  BadgeColor.teal => 'teal',
  BadgeColor.ai => 'ai',
};

/// Badge showcase (web `BadgeShowcase`).
class BadgeShowcaseSection extends ConsumerWidget {
  const BadgeShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'badge',
      title: 'Badge / Status pill',
      description: copy.sectionDescription,
      componentName: 'Badge',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShowcaseDemoGrid(
            columns: 2,
            children: [
              for (final variant in _variants)
                ShowcaseDemo(
                  label: copy.variantLabel(variant),
                  propsHint: 'variant="${_variantName(variant)}"',
                  child: ShowcaseVariantMatrix(
                    title: copy.statusColors,
                    children: [
                      for (final color in _colors)
                        AppBadge(
                          variant: variant,
                          color: color,
                          label: _colorName(color),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space8),
          ShowcaseDemo(
            label: copy.sizes,
            propsHint: 'size="sm" | "md"',
            child: Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                for (final size in _sizes)
                  AppBadge(
                    size: size,
                    color: BadgeColor.success,
                    label: _sizeName(size),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space8),
          ShowcaseDemo(
            label: copy.domainStatusMapping,
            propsHint: 'per 02-tokens',
            child: Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                for (final status in _domainStatuses)
                  AppBadge(
                    color: status.color,
                    label: _domainLabel(copy, status.labelKey),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space8),
          ShowcaseDemo(
            label: copy.dotAccessibleLabel,
            propsHint: 'variant="dot" label="Active"',
            child: Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppBadge(
                  variant: BadgeVariant.dot,
                  color: BadgeColor.success,
                  label: copy.active,
                ),
                AppBadge(
                  variant: BadgeVariant.dot,
                  color: BadgeColor.danger,
                  label: copy.noShow,
                  child: Text(copy.noShow),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _variantName(BadgeVariant variant) => switch (variant) {
  BadgeVariant.solid => 'solid',
  BadgeVariant.soft => 'soft',
  BadgeVariant.outline => 'outline',
  BadgeVariant.dot => 'dot',
};

String _sizeName(BadgeSize size) => switch (size) {
  BadgeSize.sm => 'sm',
  BadgeSize.md => 'md',
};
