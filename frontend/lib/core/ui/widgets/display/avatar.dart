import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

enum AppAvatarSize { sm, md, lg, xl }

enum AppAvatarStatus { online, away, busy, offline }

/// Circular avatar with image, initials, or fallback icon and optional status dot.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.imageUrl,
    this.initials,
    this.fallbackIcon,
    this.size = AppAvatarSize.md,
    this.status = AppAvatarStatus.offline,
    this.showStatus = false,
    this.semanticLabel,
  });

  final String? imageUrl;
  final String? initials;
  final IconData? fallbackIcon;
  final AppAvatarSize size;
  final AppAvatarStatus status;
  final bool showStatus;
  final String? semanticLabel;

  double get _dimension => switch (size) {
    AppAvatarSize.sm => 24,
    AppAvatarSize.md => 32,
    AppAvatarSize.lg => 40,
    AppAvatarSize.xl => 48,
  };

  double get _statusDimension => switch (size) {
    AppAvatarSize.sm => 6,
    AppAvatarSize.md => 8,
    AppAvatarSize.lg => 10,
    AppAvatarSize.xl => 12,
  };

  double get _statusBorderWidth => switch (size) {
    AppAvatarSize.sm => 1,
    _ => 2,
  };

  TextStyle _initialsStyle(BuildContext context) {
    final typography = context.typography;
    return switch (size) {
      AppAvatarSize.sm => typography.caption.copyWith(
        fontWeight: FontWeight.w500,
      ),
      AppAvatarSize.md => typography.bodySm.copyWith(
        fontWeight: FontWeight.w500,
      ),
      AppAvatarSize.lg => typography.body.copyWith(fontWeight: FontWeight.w500),
      AppAvatarSize.xl => typography.title.copyWith(
        fontWeight: FontWeight.w500,
      ),
    };
  }

  Color _statusColor(AppColors colors) => switch (status) {
    AppAvatarStatus.online => colors.statusSuccessFg,
    AppAvatarStatus.away => colors.statusWarningFg,
    AppAvatarStatus.busy => colors.statusDangerFg,
    AppAvatarStatus.offline => colors.iconMuted,
  };

  ({Color bg, Color fg}) _initialsSurface(String seed, AppColors colors) {
    final index = _hashString(seed) % 5;
    return switch (index) {
      0 => (bg: colors.surfaceMuted, fg: colors.textSecondary),
      1 => (bg: colors.surfaceSelected, fg: colors.textLink),
      2 => (bg: colors.statusInfoSurface, fg: colors.statusInfoFg),
      3 => (bg: colors.statusSuccessSurface, fg: colors.statusSuccessFg),
      _ => (bg: colors.statusWarningSurface, fg: colors.statusWarningFg),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dimension = _dimension;
    final label = semanticLabel ?? initials ?? 'Avatar';

    final avatarBody = _buildBody(context, colors, dimension);

    return Semantics(
      label: label,
      image: imageUrl != null,
      child: SizedBox(
        width: dimension,
        height: dimension,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatarBody,
            if (showStatus)
              PositionedDirectional(
                end: 0,
                bottom: 0,
                child: Semantics(
                  label: 'Status: ${status.name}',
                  child: Container(
                    width: _statusDimension,
                    height: _statusDimension,
                    decoration: BoxDecoration(
                      color: _statusColor(colors),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.surfaceDefault,
                        width: _statusBorderWidth,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppColors colors, double dimension) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: ClipOval(
          child: Image.network(
            imageUrl!,
            width: dimension,
            height: dimension,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildFallback(context, colors, dimension),
          ),
        ),
      );
    }

    if (initials != null && initials!.trim().isNotEmpty) {
      final text = initials!.trim().toUpperCase();
      final surface = _initialsSurface(text, colors);
      return Container(
        width: dimension,
        height: dimension,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: surface.bg,
          shape: BoxShape.circle,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Text(
          text,
          style: _initialsStyle(context).copyWith(color: surface.fg),
          maxLines: 1,
        ),
      );
    }

    return _buildFallback(context, colors, dimension);
  }

  Widget _buildFallback(
    BuildContext context,
    AppColors colors,
    double dimension,
  ) {
    return Container(
      width: dimension,
      height: dimension,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        shape: BoxShape.circle,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Icon(
        fallbackIcon ?? Icons.person_outline,
        size: dimension * 0.45,
        color: colors.iconMuted,
      ),
    );
  }

  static int _hashString(String value) {
    var hash = 0;
    for (var i = 0; i < value.length; i++) {
      hash = (hash << 5) - hash + value.codeUnitAt(i);
      hash &= 0x7FFFFFFF;
    }
    return hash;
  }
}

/// Overlapping row of avatars with optional "+N" overflow indicator.
class AppAvatarGroup extends StatelessWidget {
  const AppAvatarGroup({
    super.key,
    required this.avatars,
    this.max = 4,
    this.size = AppAvatarSize.md,
  });

  final List<AppAvatar> avatars;
  final int max;
  final AppAvatarSize size;

  double get _dimension => switch (size) {
    AppAvatarSize.sm => 24,
    AppAvatarSize.md => 32,
    AppAvatarSize.lg => 40,
    AppAvatarSize.xl => 48,
  };

  double get _overlap => switch (size) {
    AppAvatarSize.sm => AppSpacing.s2,
    AppAvatarSize.md => 10,
    AppAvatarSize.lg => AppSpacing.s3,
    AppAvatarSize.xl => 14,
  };

  TextStyle _overflowStyle(BuildContext context) {
    final typography = context.typography;
    return switch (size) {
      AppAvatarSize.sm => typography.caption.copyWith(
        fontWeight: FontWeight.w500,
      ),
      AppAvatarSize.md => typography.bodySm.copyWith(
        fontWeight: FontWeight.w500,
      ),
      AppAvatarSize.lg => typography.body.copyWith(fontWeight: FontWeight.w500),
      AppAvatarSize.xl => typography.title.copyWith(
        fontWeight: FontWeight.w500,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final visible = avatars.take(max).toList();
    final overflow = avatars.length - visible.length;
    final dimension = _dimension;

    return Semantics(
      label: 'Avatar group',
      child: SizedBox(
        height: dimension,
        width: visible.isEmpty
            ? 0
            : dimension +
                  (visible.length - 1) * (dimension - _overlap) +
                  (overflow > 0 ? dimension - _overlap : 0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < visible.length; i++)
              PositionedDirectional(
                start: i * (dimension - _overlap),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surfaceDefault, width: 2),
                  ),
                  child: visible[i],
                ),
              ),
            if (overflow > 0)
              PositionedDirectional(
                start: visible.length * (dimension - _overlap),
                child: Container(
                  width: dimension,
                  height: dimension,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surfaceMuted,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surfaceDefault, width: 2),
                  ),
                  child: Semantics(
                    label: '$overflow more',
                    child: Text(
                      '+$overflow',
                      style: _overflowStyle(
                        context,
                      ).copyWith(color: colors.textSecondary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
