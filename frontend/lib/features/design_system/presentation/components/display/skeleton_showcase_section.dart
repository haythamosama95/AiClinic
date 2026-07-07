import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_skeletonizer_zone.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _SkeletonCopy {
  const _SkeletonCopy({
    required this.description,
    required this.variantsLabel,
    required this.variantsHint,
    required this.listRowLabel,
    required this.listRowHint,
    required this.cardLayoutLabel,
    required this.cardLayoutHint,
    required this.contrastLabel,
    required this.contrastHint,
    required this.saraHassan,
  });

  final String description;
  final String variantsLabel;
  final String variantsHint;
  final String listRowLabel;
  final String listRowHint;
  final String cardLayoutLabel;
  final String cardLayoutHint;
  final String contrastLabel;
  final String contrastHint;
  final String saraHassan;
}

const _copyEn = _SkeletonCopy(
  description: 'Shape-matched placeholders with calm shimmer; static under reduced motion.',
  variantsLabel: 'Variants',
  variantsHint: 'Bone.text | Bone.circle | Bone',
  listRowLabel: 'List row layout',
  listRowHint: 'composed',
  cardLayoutLabel: 'Card layout',
  cardLayoutHint: 'composed',
  contrastLabel: 'Contrast with loaded avatar',
  contrastHint: 'loading → loaded',
  saraHassan: 'Sara Hassan',
);

const _copyAr = _SkeletonCopy(
  description: 'عناصر نائبة مطابقة للشكل مع وميض هادئ؛ ثابتة عند تقليل الحركة.',
  variantsLabel: 'الأنواع',
  variantsHint: 'Bone.text | Bone.circle | Bone',
  listRowLabel: 'تخطيط صف القائمة',
  listRowHint: 'مركّب',
  cardLayoutLabel: 'تخطيط البطاقة',
  cardLayoutHint: 'مركّب',
  contrastLabel: 'تباين مع صورة محمّلة',
  contrastHint: 'تحميل ← محمّل',
  saraHassan: 'سارة حسن',
);

_SkeletonCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Skeleton showcase (web `SkeletonShowcase`).
class SkeletonShowcaseSection extends ConsumerWidget {
  const SkeletonShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'skeleton',
      title: 'Skeleton',
      description: copy.description,
      componentName: 'Skeleton',
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: copy.variantsLabel,
            propsHint: copy.variantsHint,
            child: AppSkeletonizerZone(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: const Bone.text()),
                  const SizedBox(height: AppSpacing.space3),
                  const Bone.circle(size: 40),
                  const SizedBox(height: AppSpacing.space3),
                  Bone(width: 120, height: 80, borderRadius: BorderRadius.circular(AppRadius.md)),
                ],
              ),
            ),
          ),
          ShowcaseDemo(
            label: copy.listRowLabel,
            propsHint: copy.listRowHint,
            child: AppSkeletonizerZone(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 384),
                child: Row(
                  children: [
                    const Bone.circle(size: 32),
                    const SizedBox(width: AppSpacing.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FractionallySizedBox(widthFactor: 0.75, child: const Bone.text()),
                          SizedBox(height: AppSpacing.space2),
                          FractionallySizedBox(widthFactor: 0.5, child: const Bone.text()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ShowcaseDemo(
            label: copy.cardLayoutLabel,
            propsHint: copy.cardLayoutHint,
            child: AppSkeletonizerZone(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.borderSubtle),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Bone(height: 96, borderRadius: BorderRadius.circular(AppRadius.md)),
                        SizedBox(height: AppSpacing.space3),
                        const Bone.text(),
                        SizedBox(height: AppSpacing.space3),
                        FractionallySizedBox(widthFactor: 2 / 3, child: const Bone.text()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ShowcaseDemo(
            label: copy.contrastLabel,
            propsHint: copy.contrastHint,
            child: AppSkeletonizerZone(
              child: Row(
                children: [
                  const Bone.circle(size: 32),
                  const SizedBox(width: AppSpacing.space3),
                  AppAvatar(name: copy.saraHassan, size: AvatarSize.md),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
