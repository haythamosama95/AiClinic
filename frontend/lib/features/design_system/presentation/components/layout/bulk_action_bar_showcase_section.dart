import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_bulk_action_bar.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _BulkActionBarCopy {
  const _BulkActionBarCopy({
    required this.itemLabel,
    required this.export,
    required this.voidAction,
  });

  final String itemLabel;
  final String export;
  final String voidAction;
}

const _copyEn = _BulkActionBarCopy(
  itemLabel: 'invoices selected',
  export: 'Export',
  voidAction: 'Void',
);

const _copyAr = _BulkActionBarCopy(
  itemLabel: 'فواتير محددة',
  export: 'تصدير',
  voidAction: 'إلغاء',
);

_BulkActionBarCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Bulk action bar showcase (web `BulkActionBarShowcase`).
class BulkActionBarShowcaseSection extends ConsumerWidget {
  const BulkActionBarShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'bulk-action-bar',
      title: 'Bulk action bar',
      componentName: 'BulkActionBar',
      child: AppBulkActionBar(
        count: 3,
        itemLabel: copy.itemLabel,
        onClear: () {},
        actions: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.space2,
          children: [
            AppButton(
              size: AppButtonSize.sm,
              variant: AppButtonVariant.secondary,
              onPressed: () {},
              child: Text(copy.export),
            ),
            AppButton(
              size: AppButtonSize.sm,
              variant: AppButtonVariant.danger,
              onPressed: () {},
              child: Text(copy.voidAction),
            ),
          ],
        ),
      ),
    );
  }
}
