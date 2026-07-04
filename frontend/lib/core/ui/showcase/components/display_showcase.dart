import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class DisplayShowcase extends StatelessWidget {
  const DisplayShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShowcaseSection(
          title: 'Avatar',
          child: Wrap(
            spacing: AppSpacing.s6,
            runSpacing: AppSpacing.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final size in AppAvatarSize.values)
                AppAvatar(
                  initials: 'HA',
                  size: size,
                  status: AppAvatarStatus.online,
                  showStatus: true,
                ),
              AppAvatarGroup(
                avatars: const [
                  AppAvatar(initials: 'A'),
                  AppAvatar(initials: 'B'),
                  AppAvatar(initials: 'C'),
                  AppAvatar(initials: 'D'),
                  AppAvatar(initials: 'E'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Badge',
          child: Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            children: [
              for (final variant in AppBadgeVariant.values)
                AppBadge(label: variant.name, variant: variant, showDot: true),
              for (final variant in AppBadgeVariant.values)
                AppBadge(
                  label: variant.name,
                  variant: variant,
                  tone: AppBadgeTone.solid,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Chip',
          child: Wrap(
            spacing: AppSpacing.s2,
            children: [
              AppChip(label: Text('Default')),
              AppChip(
                label: Text('Selected'),
                selectable: true,
                selected: true,
              ),
              AppChip(
                label: Text('Removable'),
                removable: true,
                onDeleted: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Divider',
          child: Column(
            children: const [
              AppDivider(),
              SizedBox(height: AppSpacing.s4),
              AppDivider(label: Text('OR')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Kbd',
          child: Wrap(
            spacing: AppSpacing.s2,
            children: [
              AppKbd(keys: ['⌘', 'K']),
              AppKbd(keys: ['Ctrl', 'S']),
              AppKbd.single('Esc'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Progress',
          child: Column(
            children: const [
              AppProgress(value: 0.65),
              SizedBox(height: AppSpacing.s4),
              AppProgress(indeterminate: true),
              SizedBox(height: AppSpacing.s4),
              Row(
                children: [
                  AppProgress(variant: AppProgressVariant.circular, value: 0.4),
                  SizedBox(width: AppSpacing.s4),
                  AppProgress(
                    variant: AppProgressVariant.circular,
                    indeterminate: true,
                    size: AppProgressSize.md,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Skeleton',
          child: Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s4,
            children: const [
              AppSkeleton(shape: AppSkeletonShape.text, width: 200),
              AppSkeleton(shape: AppSkeletonShape.rect, width: 120, height: 80),
              AppSkeleton(
                shape: AppSkeletonShape.circle,
                width: 48,
                height: 48,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Tooltip',
          child: AppTooltip(
            message: Text('Helpful hint'),
            child: AppButton(
              onPressed: () {},
              variant: AppButtonVariant.secondary,
              child: const Text('Hover me'),
            ),
          ),
        ),
      ],
    );
  }
}
