import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/display/app_avatar.dart';

/// Overlapping row of [AppAvatar] widgets with "+N" overflow indicator.
class AppAvatarGroup extends StatelessWidget {
  const AppAvatarGroup({
    required this.children,
    this.max = 4,
    this.size = AppAvatarSize.md,
    super.key,
  });

  final List<Widget> children;
  final int max;
  final AppAvatarSize size;

  static double _overlapFor(AppAvatarSize size) => switch (size) {
    AppAvatarSize.xs => AppSpacing.s1 + AppSpacing.s0_5,
    AppAvatarSize.sm => AppSpacing.s2,
    AppAvatarSize.md => AppSpacing.s2 + AppSpacing.s0_5,
    AppAvatarSize.lg => AppSpacing.s3,
    AppAvatarSize.xl => AppSpacing.s3 + AppSpacing.s0_5,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final dimension = AppAvatar.dimensionFor(size);
    final overlap = _overlapFor(size);
    final visible = children.take(max).toList();
    final overflow = children.length - max;

    final isLtr = Directionality.of(context) == TextDirection.ltr;
    double overlapOffset(int index) =>
        (isLtr ? -1 : 1) * overlap * index;

    return Semantics(
      container: true,
      label: 'Avatar group',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < visible.length; i++)
            Transform.translate(
              offset: Offset(overlapOffset(i), 0),
              child: _AvatarRing(
                colors: colors,
                child: visible[i],
              ),
            ),
          if (overflow > 0)
            Transform.translate(
              offset: Offset(overlapOffset(visible.length), 0),
              child: Semantics(
                label: '$overflow more',
                child: _AvatarRing(
                  colors: colors,
                  child: Container(
                    width: dimension,
                    height: dimension,
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '+$overflow',
                      style: _overflowTextStyle(typography, size).copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  TextStyle _overflowTextStyle(AppTypography typography, AppAvatarSize size) {
    return switch (size) {
      AppAvatarSize.xs => typography.caption.copyWith(
        fontSize: AppSpacing.s2 + AppSpacing.s0_5,
      ),
      AppAvatarSize.sm => typography.caption,
      AppAvatarSize.md => typography.bodySm,
      AppAvatarSize.lg => typography.body,
      AppAvatarSize.xl => typography.title,
    };
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({required this.colors, required this.child});

  final AppColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.surfaceDefault,
          width: AppSpacing.sPx + AppSpacing.sPx,
        ),
      ),
      child: child,
    );
  }
}
