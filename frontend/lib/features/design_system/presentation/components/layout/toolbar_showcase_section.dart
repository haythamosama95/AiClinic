import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_chip.dart';
import 'package:ai_clinic/core/ui/components/app_search_input.dart';
import 'package:ai_clinic/core/ui/components/app_toolbar.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ToolbarCopy {
  const _ToolbarCopy({
    required this.searchPlaceholder,
    required this.active,
    required this.downtown,
    required this.filters,
  });

  final String searchPlaceholder;
  final String active;
  final String downtown;
  final String filters;
}

const _copyEn = _ToolbarCopy(
  searchPlaceholder: 'Search patients…',
  active: 'Active',
  downtown: 'Downtown',
  filters: 'Filters',
);

const _copyAr = _ToolbarCopy(
  searchPlaceholder: 'ابحث عن مرضى…',
  active: 'نشط',
  downtown: 'وسط البلد',
  filters: 'تصفية',
);

_ToolbarCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Toolbar showcase (web `ToolbarShowcase`).
class ToolbarShowcaseSection extends ConsumerWidget {
  const ToolbarShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'toolbar',
      title: 'Toolbar / filter bar',
      componentName: 'Toolbar',
      child: AppToolbar(
        start: Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 224,
              child: AppSearchInput(placeholder: copy.searchPlaceholder),
            ),
            AppChip(
              selectable: true,
              selected: true,
              child: Text(copy.active),
            ),
            AppChip(
              removable: true,
              onRemove: () {},
              child: Text(copy.downtown),
            ),
          ],
        ),
        end: AppButton(
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.sm,
          leadingIcon: const Icon(Icons.search, size: 14),
          onPressed: () {},
          child: Text(copy.filters),
        ),
      ),
    );
  }
}
