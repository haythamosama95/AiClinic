import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

const _sizes = <AvatarSize>[
  AvatarSize.xs,
  AvatarSize.sm,
  AvatarSize.md,
  AvatarSize.lg,
  AvatarSize.xl,
];

const _statuses = <AvatarStatus>[
  AvatarStatus.online,
  AvatarStatus.offline,
  AvatarStatus.busy,
  AvatarStatus.away,
];

const _team = <({String name})>[
  (name: 'Sara Hassan'),
  (name: 'Omar Khalil'),
  (name: 'Layla Nour'),
  (name: 'Youssef Ali'),
  (name: 'Nadia Farid'),
];

class _AvatarCopy {
  const _AvatarCopy({
    required this.description,
    required this.sizesLabel,
    required this.sizesHint,
    required this.initialsTitle,
    required this.saraHassan,
    required this.statusDotLabel,
    required this.statusDotHint,
    required this.avatarGroupLabel,
    required this.avatarGroupHint,
    required this.deterministicColorLabel,
    required this.deterministicColorHint,
    required this.online,
    required this.offline,
    required this.busy,
    required this.away,
  });

  final String description;
  final String sizesLabel;
  final String sizesHint;
  final String initialsTitle;
  final String saraHassan;
  final String statusDotLabel;
  final String statusDotHint;
  final String avatarGroupLabel;
  final String avatarGroupHint;
  final String deterministicColorLabel;
  final String deterministicColorHint;
  final String online;
  final String offline;
  final String busy;
  final String away;

  String statusLabel(AvatarStatus status) {
    return switch (status) {
      AvatarStatus.online => online,
      AvatarStatus.offline => offline,
      AvatarStatus.busy => busy,
      AvatarStatus.away => away,
    };
  }
}

const _copyEn = _AvatarCopy(
  description: 'Image or initials fallback with optional status dot and stacked groups.',
  sizesLabel: 'Sizes',
  sizesHint: 'size="xs"…"xl"',
  initialsTitle: 'Initials',
  saraHassan: 'Sara Hassan',
  statusDotLabel: 'Status dot',
  statusDotHint: 'showStatus',
  avatarGroupLabel: 'Avatar group',
  avatarGroupHint: 'max={4}',
  deterministicColorLabel: 'Deterministic initials color',
  deterministicColorHint: 'hash from name',
  online: 'online',
  offline: 'offline',
  busy: 'busy',
  away: 'away',
);

const _copyAr = _AvatarCopy(
  description: 'صورة أو أحرف بديلة مع نقطة حالة اختيارية ومجموعات متداخلة.',
  sizesLabel: 'الأحجام',
  sizesHint: 'size="xs"…"xl"',
  initialsTitle: 'الأحرف الأولى',
  saraHassan: 'سارة حسن',
  statusDotLabel: 'نقطة الحالة',
  statusDotHint: 'showStatus',
  avatarGroupLabel: 'مجموعة الصور',
  avatarGroupHint: 'max={4}',
  deterministicColorLabel: 'لون أحرف أولية محدد',
  deterministicColorHint: 'تجزئة من الاسم',
  online: 'متصل',
  offline: 'غير متصل',
  busy: 'مشغول',
  away: 'بعيد',
);

_AvatarCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Avatar showcase (web `AvatarShowcase`).
class AvatarShowcaseSection extends ConsumerWidget {
  const AvatarShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'avatar',
      title: 'Avatar / Group',
      description: copy.description,
      componentName: 'Avatar · AvatarGroup',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShowcaseDemo(
            label: copy.sizesLabel,
            propsHint: copy.sizesHint,
            child: ShowcaseVariantMatrix(
              title: copy.initialsTitle,
              children: [
                for (final size in _sizes)
                  AppAvatar(name: copy.saraHassan, size: size),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space8),
          ShowcaseDemo(
            label: copy.statusDotLabel,
            propsHint: copy.statusDotHint,
            child: Wrap(
              spacing: AppSpacing.space4,
              runSpacing: AppSpacing.space4,
              children: [
                for (final status in _statuses)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppAvatar(
                        name: 'Omar Khalil',
                        showStatus: true,
                        status: status,
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        copy.statusLabel(status),
                        style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space8),
          ShowcaseDemoGrid(
            children: [
              ShowcaseDemo(
                label: copy.avatarGroupLabel,
                propsHint: copy.avatarGroupHint,
                child: AppAvatarGroup(
                  max: 4,
                  size: AvatarSize.md,
                  children: [
                    for (final member in _team)
                      AppAvatar(name: member.name, size: AvatarSize.md),
                  ],
                ),
              ),
              ShowcaseDemo(
                label: copy.deterministicColorLabel,
                propsHint: copy.deterministicColorHint,
                child: Wrap(
                  spacing: AppSpacing.space2,
                  runSpacing: AppSpacing.space2,
                  children: [
                    for (final member in _team.take(4))
                      AppAvatar(name: member.name),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
