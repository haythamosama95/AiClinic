import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_loading_overlay.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _LoadingOverlayCopy {
  const _LoadingOverlayCopy({
    required this.loadingLabel,
    required this.contentBeneath,
    required this.toggleLoading,
  });

  final String loadingLabel;
  final String contentBeneath;
  final String toggleLoading;
}

const _copyEn = _LoadingOverlayCopy(
  loadingLabel: 'Loading patients…',
  contentBeneath: 'Content beneath overlay',
  toggleLoading: 'Toggle loading',
);

const _copyAr = _LoadingOverlayCopy(
  loadingLabel: 'جارٍ تحميل المرضى…',
  contentBeneath: 'محتوى تحت طبقة التحميل',
  toggleLoading: 'تبديل التحميل',
);

_LoadingOverlayCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Loading overlay showcase (web `LoadingOverlayShowcase`).
class LoadingOverlayShowcaseSection extends ConsumerStatefulWidget {
  const LoadingOverlayShowcaseSection({super.key});

  @override
  ConsumerState<LoadingOverlayShowcaseSection> createState() => _LoadingOverlayShowcaseSectionState();
}

class _LoadingOverlayShowcaseSectionState extends ConsumerState<LoadingOverlayShowcaseSection> {
  var _scoped = true;

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'loading-overlay',
      title: 'Loading overlay',
      componentName: 'LoadingOverlay',
      child: ShowcaseDemo(
        label: 'Scoped',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppLoadingOverlay(
              loading: _scoped,
              scoped: true,
              label: copy.loadingLabel,
              child: SizedBox(
                width: double.infinity,
                height: AppSpacing.space16 * 2,
                child: AppCard(
                  padding: CardPadding.sm,
                  child: Text(
                    copy.contentBeneath,
                    style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            AppButton(
              size: AppButtonSize.sm,
              variant: AppButtonVariant.ghost,
              onPressed: () => setState(() => _scoped = !_scoped),
              child: Text(copy.toggleLoading),
            ),
          ],
        ),
      ),
    );
  }
}
