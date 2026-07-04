import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Visual variants shared by [AppButton] and the split-button primary segment.
enum AppButtonVariant {
  primary,
  secondary,
  ghost,
  danger,
  ai,
  link,
}

/// Height scale for labeled buttons and split-button segments.
enum AppButtonSize {
  sm,
  md,
  lg,
}

/// Visual variants for square icon-only buttons.
enum AppIconButtonVariant {
  ghost,
  secondary,
  danger,
  ai,
}

/// Square dimension scale for icon-only buttons.
enum AppIconButtonSize {
  sm,
  md,
  lg,
}

/// Resolved metrics and colors for action buttons.
abstract final class AppButtonShared {
  static double height(AppButtonSize size) => switch (size) {
    AppButtonSize.sm => AppSpacing.s8 - AppSpacing.s1,
    AppButtonSize.md => AppSpacing.s8 + AppSpacing.s1,
    AppButtonSize.lg => AppSpacing.s10 + AppSpacing.s1,
  };

  static double minWidth(AppButtonSize size) => switch (size) {
    AppButtonSize.sm => AppSpacing.s16 + AppSpacing.s2,
    AppButtonSize.md => AppSpacing.s16 + AppSpacing.s6,
    AppButtonSize.lg => AppSpacing.s16 + AppSpacing.s10,
  };

  static EdgeInsetsDirectional padding(AppButtonSize size, AppButtonVariant variant) {
    if (variant == AppButtonVariant.link) {
      return EdgeInsetsDirectional.zero;
    }
    return switch (size) {
      AppButtonSize.sm => const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s2),
      AppButtonSize.md => const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s3),
      AppButtonSize.lg => const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s4),
    };
  }

  static double gap(AppButtonSize size) => size == AppButtonSize.sm ? AppSpacing.s1 + AppSpacing.s0_5 : AppSpacing.s2;

  static TextStyle textStyle(BuildContext context, AppButtonSize size) {
    final typography = context.typography;
    return size == AppButtonSize.sm ? typography.bodySm : typography.bodyStrong;
  }

  static double iconDimension(AppButtonSize size) =>
      size == AppButtonSize.lg ? AppIconSize.md.value : AppIconSize.sm.value;

  static double iconButtonDimension(AppIconButtonSize size) => switch (size) {
    AppIconButtonSize.sm => AppSpacing.s8 - AppSpacing.s1,
    AppIconButtonSize.md => AppSpacing.s8,
    AppIconButtonSize.lg => AppSpacing.s10,
  };

  static double iconButtonIconDimension(AppIconButtonSize size) =>
      size == AppIconButtonSize.lg ? AppIconSize.md.value : AppIconSize.sm.value;

  static AppFocusRingVariant focusRingVariant(AppButtonVariant variant) =>
      variant == AppButtonVariant.ai ? AppFocusRingVariant.ai : AppFocusRingVariant.standard;

  static AppFocusRingVariant iconButtonFocusRingVariant(AppIconButtonVariant variant) =>
      variant == AppIconButtonVariant.ai ? AppFocusRingVariant.ai : AppFocusRingVariant.standard;

  static Color background(
    AppColors colors,
    AppButtonVariant variant,
    Set<WidgetState> states, {
    required bool disabled,
  }) {
    if (disabled) {
      return variant == AppButtonVariant.link ? Colors.transparent : colors.actionDisabledBg;
    }

    if (states.contains(WidgetState.pressed)) {
      return switch (variant) {
        AppButtonVariant.primary => colors.actionPrimaryActive,
        AppButtonVariant.secondary => colors.surfaceMuted,
        AppButtonVariant.ghost => colors.surfaceMuted,
        AppButtonVariant.danger => colors.actionDangerActive,
        AppButtonVariant.ai => colors.actionAi,
        AppButtonVariant.link => Colors.transparent,
      };
    }

    if (states.contains(WidgetState.hovered)) {
      return switch (variant) {
        AppButtonVariant.primary => colors.actionPrimaryHover,
        AppButtonVariant.secondary => colors.surfaceHover,
        AppButtonVariant.ghost => colors.actionSubtleHover,
        AppButtonVariant.danger => colors.actionDangerHover,
        AppButtonVariant.ai => colors.actionAiHover,
        AppButtonVariant.link => Colors.transparent,
      };
    }

    return switch (variant) {
      AppButtonVariant.primary => colors.actionPrimary,
      AppButtonVariant.secondary => colors.actionSecondary,
      AppButtonVariant.ghost => Colors.transparent,
      AppButtonVariant.danger => colors.actionDanger,
      AppButtonVariant.ai => colors.actionAi,
      AppButtonVariant.link => Colors.transparent,
    };
  }

  static Color foreground(
    AppColors colors,
    AppButtonVariant variant,
    Set<WidgetState> states, {
    required bool disabled,
  }) {
    if (disabled) {
      return colors.textDisabled;
    }

    if (variant == AppButtonVariant.link &&
        states.contains(WidgetState.pressed)) {
      return colors.textPrimary;
    }

    return switch (variant) {
      AppButtonVariant.primary => colors.actionPrimaryFg,
      AppButtonVariant.secondary => colors.actionSecondaryFg,
      AppButtonVariant.ghost => colors.textPrimary,
      AppButtonVariant.danger => colors.actionDangerFg,
      AppButtonVariant.ai => colors.actionAiFg,
      AppButtonVariant.link => colors.textLink,
    };
  }

  static Color? borderColor(
    AppColors colors,
    AppButtonVariant variant, {
    required bool disabled,
  }) {
    if (disabled || variant == AppButtonVariant.link) return null;
    if (variant == AppButtonVariant.secondary) return colors.borderDefault;
    if (variant == AppButtonVariant.ghost) return null;
    return null;
  }

  static Color iconButtonBackground(
    AppColors colors,
    AppIconButtonVariant variant,
    Set<WidgetState> states, {
    required bool disabled,
  }) {
    if (disabled) return colors.actionDisabledBg;

    if (states.contains(WidgetState.pressed)) {
      return switch (variant) {
        AppIconButtonVariant.ghost => colors.surfaceMuted,
        AppIconButtonVariant.secondary => colors.surfaceMuted,
        AppIconButtonVariant.danger => colors.statusDangerSurface,
        AppIconButtonVariant.ai => colors.surfaceAi,
      };
    }

    if (states.contains(WidgetState.hovered)) {
      return switch (variant) {
        AppIconButtonVariant.ghost => colors.actionSubtleHover,
        AppIconButtonVariant.secondary => colors.surfaceHover,
        AppIconButtonVariant.danger => colors.statusDangerSurface,
        AppIconButtonVariant.ai => colors.surfaceAi,
      };
    }

    return switch (variant) {
      AppIconButtonVariant.ghost => Colors.transparent,
      AppIconButtonVariant.secondary => colors.actionSecondary,
      AppIconButtonVariant.danger => Colors.transparent,
      AppIconButtonVariant.ai => Colors.transparent,
    };
  }

  static Color iconButtonForeground(
    AppColors colors,
    AppIconButtonVariant variant,
    Set<WidgetState> states, {
    required bool disabled,
  }) {
    if (disabled) return colors.textDisabled;

    final hoveredOrPressed =
        states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed);

    return switch (variant) {
      AppIconButtonVariant.ghost =>
        hoveredOrPressed ? colors.textPrimary : colors.iconDefault,
      AppIconButtonVariant.secondary =>
        hoveredOrPressed ? colors.textPrimary : colors.iconDefault,
      AppIconButtonVariant.danger => colors.statusDangerFg,
      AppIconButtonVariant.ai => colors.textAi,
    };
  }

  static Color? iconButtonBorderColor(
    AppColors colors,
    AppIconButtonVariant variant, {
    required bool disabled,
  }) {
    if (disabled) return null;
    if (variant == AppIconButtonVariant.secondary) return colors.borderDefault;
    return null;
  }

  static BoxDecoration decoration({
    required Color background,
    required BorderRadius borderRadius,
    Color? borderColor,
    bool error = false,
    required AppColors colors,
  }) {
    return BoxDecoration(
      color: background,
      borderRadius: borderRadius,
      border: borderColor != null ? Border.all(color: borderColor) : null,
      boxShadow: error
          ? [
              BoxShadow(
                color: colors.statusDangerBorder,
                spreadRadius: AppSpacing.s0_5,
              ),
              BoxShadow(
                color: colors.surfaceDefault,
                spreadRadius: AppSpacing.s1,
              ),
              BoxShadow(
                color: colors.statusDangerBorder,
                spreadRadius: AppSpacing.s0_5,
              ),
            ]
          : null,
    );
  }
}
