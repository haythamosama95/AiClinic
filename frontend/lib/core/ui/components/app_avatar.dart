import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

enum AvatarSize { xs, sm, md, lg, xl }

enum AvatarStatus { online, offline, busy, away }

/// Application-owned avatar (`04-components` D5).
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    required this.name,
    this.size = AvatarSize.md,
    this.status = AvatarStatus.offline,
    this.showStatus = false,
    this.src,
    super.key,
  });

  final String name;
  final AvatarSize size;
  final AvatarStatus status;
  final bool showStatus;
  final String? src;

  static const _sizes = <AvatarSize, double>{
    AvatarSize.xs: AppSpacing.space5,
    AvatarSize.sm: AppSpacing.space6,
    AvatarSize.md: AppSpacing.space8,
    AvatarSize.lg: AppSpacing.space10,
    AvatarSize.xl: AppSpacing.space12,
  };

  static const _overlapMargins = <AvatarSize, double>{
    AvatarSize.xs: 6,
    AvatarSize.sm: AppSpacing.space2,
    AvatarSize.md: 10,
    AvatarSize.lg: AppSpacing.space3,
    AvatarSize.xl: 14,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dimension = _sizes[size]!;
    final initials = _initials(name);
    final surface = _initialsSurface(context, name);

    Widget avatar;
    if (src != null && src!.isNotEmpty) {
      avatar = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: ClipOval(
          child: Image.network(
            src!,
            width: dimension,
            height: dimension,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _InitialsAvatar(size: size, dimension: dimension, initials: initials, surface: surface),
          ),
        ),
      );
    } else {
      avatar = _InitialsAvatar(size: size, dimension: dimension, initials: initials, surface: surface);
    }

    if (!showStatus) {
      return Semantics(image: true, label: name, child: avatar);
    }

    final statusSpec = _statusSpec(size);
    final statusColor = _statusColor(colors, status, Theme.of(context).brightness);

    return Semantics(
      image: true,
      label: name,
      child: SizedBox(
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
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    border: Border.all(color: colors.surfaceDefault, width: statusSpec.borderWidth),
                  ),
                  child: SizedBox(width: statusSpec.diameter, height: statusSpec.diameter),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.length >= 2 ? parts.first.substring(0, 2).toUpperCase() : parts.first[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static int _hashString(String value) {
    var hash = 0;
    for (var i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash + value.codeUnitAt(i)).toSigned(32);
    }
    return hash.abs();
  }

  static _AvatarSurface _initialsSurface(BuildContext context, String name) {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;
    final index = _hashString(name) % 5;

    return switch (index) {
      0 => _AvatarSurface(colors.surfaceMuted, colors.textSecondary),
      1 => _AvatarSurface(colors.surfaceSelected, colors.textLink),
      2 =>
        brightness == Brightness.dark
            ? const _AvatarSurface(AppColorPrimitives.statusInfoSurfaceDark, AppColorPrimitives.statusInfoFgDark)
            : const _AvatarSurface(AppColorPrimitives.blue50, AppColorPrimitives.blue700),
      3 =>
        brightness == Brightness.dark
            ? const _AvatarSurface(AppColorPrimitives.statusSuccessSurfaceDark, AppColorPrimitives.statusSuccessFgDark)
            : const _AvatarSurface(AppColorPrimitives.green50, AppColorPrimitives.green700),
      _ =>
        brightness == Brightness.dark
            ? const _AvatarSurface(AppColorPrimitives.statusWarningSurfaceDark, AppColorPrimitives.statusWarningFgDark)
            : const _AvatarSurface(AppColorPrimitives.amber50, AppColorPrimitives.amber700),
    };
  }

  static TextStyle _textStyleForSize(BuildContext context, AvatarSize size) {
    return switch (size) {
      AvatarSize.xs => AppTypography.bodySm(context).copyWith(fontSize: 10, fontWeight: FontWeight.w500),
      AvatarSize.sm => AppTypography.caption(context).copyWith(fontWeight: FontWeight.w500),
      AvatarSize.md => AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w500),
      AvatarSize.lg => AppTypography.body(context).copyWith(fontWeight: FontWeight.w500),
      AvatarSize.xl => AppTypography.title(context).copyWith(fontWeight: FontWeight.w500),
    };
  }

  static Color _statusColor(AppSemanticColors colors, AvatarStatus status, Brightness brightness) {
    return switch (status) {
      AvatarStatus.online => colors.statusSuccessFg,
      AvatarStatus.offline => colors.iconMuted,
      AvatarStatus.busy => colors.statusDangerFg,
      AvatarStatus.away =>
        brightness == Brightness.dark ? AppColorPrimitives.statusWarningFgDark : AppColorPrimitives.amber500,
    };
  }

  static _StatusDotSpec _statusSpec(AvatarSize size) {
    return switch (size) {
      AvatarSize.xs || AvatarSize.sm => const _StatusDotSpec(diameter: 6, borderWidth: 1),
      AvatarSize.md => const _StatusDotSpec(diameter: 8, borderWidth: 2),
      AvatarSize.lg => const _StatusDotSpec(diameter: 10, borderWidth: 2),
      AvatarSize.xl => const _StatusDotSpec(diameter: 12, borderWidth: 2),
    };
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.size, required this.dimension, required this.initials, required this.surface});

  final AvatarSize size;
  final double dimension;
  final String initials;
  final _AvatarSurface surface;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: surface.background,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: SizedBox(
        width: dimension,
        height: dimension,
        child: Center(
          child: Text(initials, style: AppAvatar._textStyleForSize(context, size).copyWith(color: surface.foreground)),
        ),
      ),
    );
  }
}

/// Stacked avatars with optional overflow pill (`+N`).
class AppAvatarGroup extends StatelessWidget {
  const AppAvatarGroup({required this.children, this.max = 4, this.size = AvatarSize.md, super.key});

  final List<Widget> children;
  final int max;
  final AvatarSize size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dimension = AppAvatar._sizes[size]!;
    final overlap = AppAvatar._overlapMargins[size]!;
    final visible = children.take(max).toList();
    final overflow = children.length - max;

    final step = dimension - overlap;
    final count = visible.length + (overflow > 0 ? 1 : 0);

    return Semantics(
      container: true,
      label: 'Avatar group',
      child: SizedBox(
        width: dimension + (count - 1) * step,
        height: dimension,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < visible.length; i++)
              PositionedDirectional(
                start: i * step,
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
                start: visible.length * step,
                child: Semantics(
                  label: '$overflow more',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surfaceMuted,
                      border: Border.all(color: colors.surfaceDefault, width: 2),
                    ),
                    child: SizedBox(
                      width: dimension,
                      height: dimension,
                      child: Center(
                        child: Text(
                          '+$overflow',
                          style: AppAvatar._textStyleForSize(context, size).copyWith(color: colors.textSecondary),
                        ),
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
}

class _AvatarSurface {
  const _AvatarSurface(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

class _StatusDotSpec {
  const _StatusDotSpec({required this.diameter, required this.borderWidth});

  final double diameter;
  final double borderWidth;
}
