import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_section_header.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _SectionHeaderCopy {
  const _SectionHeaderCopy({
    required this.title,
    required this.description,
    required this.addService,
  });

  final String title;
  final String description;
  final String addService;
}

const _copyEn = _SectionHeaderCopy(
  title: 'Branch configuration',
  description: 'Manage services and pricing per branch.',
  addService: 'Add service',
);

const _copyAr = _SectionHeaderCopy(
  title: 'إعدادات الفرع',
  description: 'أدر الخدمات والتسعير لكل فرع.',
  addService: 'إضافة خدمة',
);

_SectionHeaderCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Section header showcase (web `SectionHeaderShowcase`).
class SectionHeaderShowcaseSection extends ConsumerWidget {
  const SectionHeaderShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'section-header',
      title: 'Section header',
      componentName: 'SectionHeader',
      child: AppSectionHeader(
        title: copy.title,
        description: copy.description,
        actions: AppButton(
          size: AppButtonSize.sm,
          onPressed: () {},
          child: Text(copy.addService),
        ),
      ),
    );
  }
}
