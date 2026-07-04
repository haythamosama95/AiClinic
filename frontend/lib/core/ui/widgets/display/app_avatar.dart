import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Size scale for [AppAvatar] — maps to 20/24/32/40/48 logical pixels.
enum AppAvatarSize {
  xs,
  sm,
  md,
  lg,
  xl,
}

/// Presence indicator shown on [AppAvatar].
enum AppAvatarStatus {
  online,
  offline,
  busy,
  away,
}

/// Circular avatar with image or deterministic initials fallback.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    required this.name,
    this.image,
    this.size = AppAvatarSize.md,
    this.status = AppAvatarStatus.offline,
    this.showStatus = false,
    super.key,
  });

  final String name;
  final ImageProvider? image;
  final AppAvatarSize size;
  final AppAvatarStatus status;
  final bool showStatus;

  static double dimensionFor(AppAvatarSize size) => switch (size) {
    AppAvatarSize.xs => AppSpacing.s5,
    AppAvatarSize.sm => AppSpacing.s6,
    AppAvatarSize.md => AppSpacing.s8,
    AppAvatarSize.lg => AppSpacing.s10,
    AppAvatarSize.xl => AppSpacing.s12,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final dimension = dimensionFor(size);
    final initials = _initialsFor(name);
    final surface = _initialsSurface(colors, name);

    Widget avatar = Container(
      width: dimension,
      height: dimension,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.borderSubtle),
        color: image == null ? surface.background : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image(
              image: image!,
              fit: BoxFit.cover,
              semanticLabel: name,
            )
          : Center(
              child: Text(
                initials,
                style: _textStyle(typography, size).copyWith(
                  color: surface.foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
    );

    if (!showStatus) return avatar;

    final statusSize = _statusDotSize(size);
    final statusBorder = _statusBorderWidth(size);
    final statusColor = _statusColor(colors, status);

    return SizedBox(
      width: dimension,
      height: dimension,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: Semantics(
              label: 'Status: ${status.name}',
              child: Container(
                width: statusSize,
                height: statusSize,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.surfaceDefault,
                    width: statusBorder,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final list = parts.toList();
    if (list.isEmpty) return '?';
    if (list.length == 1) {
      final word = list.first;
      return word.substring(0, word.length < 2 ? word.length : 2).toUpperCase();
    }
    return '${list.first[0]}${list.last[0]}'.toUpperCase();
  }

  static int _hashString(String value) {
    var hash = 0;
    for (var i = 0; i < value.length; i++) {
      hash = (hash << 5) - hash + value.codeUnitAt(i);
      hash |= 0;
    }
    return hash.abs();
  }

  static ({Color background, Color foreground}) _initialsSurface(
    AppColors colors,
    String name,
  ) {
    final surfaces = [
      (background: colors.surfaceMuted, foreground: colors.textSecondary),
      (background: colors.surfaceSelected, foreground: colors.textLink),
      (background: colors.statusInfoSurface, foreground: colors.statusInfoFg),
      (
        background: colors.statusSuccessSurface,
        foreground: colors.statusSuccessFg,
      ),
      (
        background: colors.statusWarningSurface,
        foreground: colors.statusWarningFg,
      ),
    ];
    return surfaces[_hashString(name) % surfaces.length];
  }

  static TextStyle _textStyle(AppTypography typography, AppAvatarSize size) {
    return switch (size) {
      AppAvatarSize.xs => typography.caption.copyWith(
        fontSize: AppSpacing.s2 + AppSpacing.s0_5,
        height: 1,
      ),
      AppAvatarSize.sm => typography.caption,
      AppAvatarSize.md => typography.bodySm,
      AppAvatarSize.lg => typography.body,
      AppAvatarSize.xl => typography.title,
    };
  }

  static double _statusDotSize(AppAvatarSize size) => switch (size) {
    AppAvatarSize.xs || AppAvatarSize.sm => AppSpacing.s1 + AppSpacing.s0_5,
    AppAvatarSize.md => AppSpacing.s2,
    AppAvatarSize.lg => AppSpacing.s2 + AppSpacing.s0_5,
    AppAvatarSize.xl => AppSpacing.s3,
  };

  static double _statusBorderWidth(AppAvatarSize size) => switch (size) {
    AppAvatarSize.xs || AppAvatarSize.sm => AppSpacing.sPx,
    AppAvatarSize.md ||
    AppAvatarSize.lg ||
    AppAvatarSize.xl =>
      AppSpacing.sPx + AppSpacing.sPx,
  };

  static Color _statusColor(AppColors colors, AppAvatarStatus status) {
    return switch (status) {
      AppAvatarStatus.online => colors.statusSuccessFg,
      AppAvatarStatus.offline => colors.iconMuted,
      AppAvatarStatus.busy => colors.statusDangerFg,
      AppAvatarStatus.away => colors.statusWarningFg,
    };
  }
}
