import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _CardCopy {
  const _CardCopy({
    required this.sectionDescription,
    required this.cardTitle,
    required this.flatText,
    required this.raisedText,
    required this.interactiveText,
    required this.aiText,
  });

  final String sectionDescription;
  final String cardTitle;
  final String flatText;
  final String raisedText;
  final String interactiveText;
  final String aiText;

  String variantText(CardVariant variant) => switch (variant) {
        CardVariant.flat => flatText,
        CardVariant.raised => raisedText,
        CardVariant.interactive => interactiveText,
        CardVariant.ai => aiText,
      };
}

const _copyEn = _CardCopy(
  sectionDescription:
      'Grouped surfaces with flat, raised, interactive, and AI variants.',
  cardTitle: 'Card title',
  flatText: 'Supporting content for the flat variant.',
  raisedText: 'Supporting content for the raised variant.',
  interactiveText: 'Supporting content for the interactive variant.',
  aiText: 'Supporting content for the ai variant.',
);

const _copyAr = _CardCopy(
  sectionDescription:
      'أسطح مجمّعة بمتغيرات مسطحة ومرتفعة وتفاعلية وذكاء اصطناعي.',
  cardTitle: 'عنوان البطاقة',
  flatText: 'محتوى داعم للمتغير المسطح.',
  raisedText: 'محتوى داعم للمتغير المرتفع.',
  interactiveText: 'محتوى داعم للمتغير التفاعلي.',
  aiText: 'محتوى داعم لمتغير الذكاء الاصطناعي.',
);

_CardCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

String _variantName(CardVariant v) => switch (v) {
      CardVariant.flat => 'flat',
      CardVariant.raised => 'raised',
      CardVariant.interactive => 'interactive',
      CardVariant.ai => 'ai',
    };

/// Card showcase (web `CardShowcase` in `DataDisplayShowcase.tsx`).
class CardShowcaseSection extends ConsumerWidget {
  const CardShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'card',
      title: 'Card',
      description: copy.sectionDescription,
      componentName: 'Card',
      child: ShowcaseDemoGrid(
        columns: 2,
        children: [
          for (final variant in CardVariant.values)
            ShowcaseDemo(
              label: _variantName(variant),
              propsHint: 'variant="${_variantName(variant)}"',
              child: SizedBox(
                width: double.infinity,
                child: AppCard(
                  variant: variant,
                  padding: CardPadding.sm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        copy.cardTitle,
                        style: AppTypography.bodyStrong(context).copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        copy.variantText(variant),
                        style: AppTypography.bodySm(context).copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
