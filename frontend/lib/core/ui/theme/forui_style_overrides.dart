import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'forui_accent_colors.dart';

/// Clinic-specific forui style overrides that align hover and surface colors with design tokens.
abstract final class ForuiStyleOverrides {
  static FButtonStyles buttonStyles({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required bool touch,
  }) {
    final accent = colors.accentColors.accent;
    final inherited = FButtonStyles.inherit(colors: colors, typography: typography, style: style, touch: touch);

    return FButtonStyles(
      FVariants.from(
        inherited.primary,
        variants: {
          [FButtonVariant.primary]: inherited.primary,
          [FButtonVariant.secondary]: inherited.secondary,
          [FButtonVariant.destructive]: inherited.destructive,
          [FButtonVariant.outline]: _outlineButtonSizeStyles(
            colors: colors,
            typography: typography,
            style: style,
            touch: touch,
            accent: accent,
          ),
          [FButtonVariant.ghost]: _ghostButtonSizeStyles(
            colors: colors,
            typography: typography,
            style: style,
            touch: touch,
            accent: accent,
          ),
        },
      ),
    );
  }

  static FItemStyles itemStyles({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required bool touch,
  }) {
    final accent = colors.accentColors.accent;
    final primary = _interactiveItemStyle(
      colors: colors,
      typography: typography,
      style: style,
      touch: touch,
      hoverColor: accent,
      backgroundColor: colors.background,
    );

    return FItemStyles(
      FVariants.from(
        primary,
        variants: {
          [FItemVariant.primary]: primary,
          [FItemVariant.destructive]: _destructiveItemDelta(colors: colors, typography: typography, touch: touch),
        },
      ),
    );
  }

  static FTileStyles tileStyles({required FColors colors, required FTypography typography, required FStyle style}) {
    final accent = colors.accentColors.accent;
    final primary = _tileStyle(colors: colors, typography: typography, style: style, hoverColor: accent);

    return FTileStyles(
      FVariants.from(
        primary,
        variants: {
          [FItemVariant.primary]: primary,
          [FItemVariant.destructive]: _destructiveTileDelta(colors: colors, typography: typography),
        },
      ),
    );
  }

  static FItemGroupStyle itemGroupStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required FHapticFeedback hapticFeedback,
    required bool touch,
  }) {
    final inherited = FItemGroupStyle.inherit(
      colors: colors,
      typography: typography,
      style: style,
      hapticFeedback: hapticFeedback,
      touch: touch,
    );

    return FItemGroupStyle(
      decoration: inherited.decoration,
      dividerColor: inherited.dividerColor,
      dividerWidth: inherited.dividerWidth,
      itemStyles: itemStyles(colors: colors, typography: typography, style: style, touch: touch),
      slideableItems: inherited.slideableItems,
      slidePressHapticFeedback: inherited.slidePressHapticFeedback,
      spacing: inherited.spacing,
    );
  }

  static FTileGroupStyle tileGroupStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required FHapticFeedback hapticFeedback,
  }) {
    final inherited = FTileGroupStyle.inherit(
      colors: colors,
      typography: typography,
      style: style,
      hapticFeedback: hapticFeedback,
    );

    return FTileGroupStyle(
      decoration: inherited.decoration,
      dividerColor: inherited.dividerColor,
      dividerWidth: inherited.dividerWidth,
      tileStyles: _tileGroupTileStyles(colors: colors, typography: typography, style: style),
      slideableTiles: inherited.slideableTiles,
      slidePressHapticFeedback: inherited.slidePressHapticFeedback,
      labelTextStyle: inherited.labelTextStyle,
      descriptionTextStyle: inherited.descriptionTextStyle,
      errorTextStyle: inherited.errorTextStyle,
      labelPadding: inherited.labelPadding,
      descriptionPadding: inherited.descriptionPadding,
      errorPadding: inherited.errorPadding,
      childPadding: inherited.childPadding,
      labelMotion: inherited.labelMotion,
    );
  }

  static FPopoverMenuStyle popoverMenuStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required FHapticFeedback hapticFeedback,
    required bool touch,
  }) {
    final inherited = FPopoverMenuStyle.inherit(
      colors: colors,
      style: style,
      typography: typography,
      hapticFeedback: hapticFeedback,
      touch: touch,
    );

    return FPopoverMenuStyle(
      itemGroupStyle: _popoverMenuItemGroupStyle(
        colors: colors,
        typography: typography,
        style: style,
        hapticFeedback: hapticFeedback,
        touch: touch,
      ),
      tileGroupStyle: inherited.tileGroupStyle,
      decoration: inherited.decoration,
      hapticFeedback: inherited.hapticFeedback,
      minWidth: inherited.minWidth,
      maxWidth: inherited.maxWidth,
      hoverEnterDuration: inherited.hoverEnterDuration,
      menuMotion: inherited.menuMotion,
      barrierFilter: inherited.barrierFilter,
      backgroundFilter: inherited.backgroundFilter,
      popoverPadding: inherited.popoverPadding,
      motion: inherited.motion,
    );
  }

  static FSelectStyle selectStyle({
    required FColors colors,
    required FIcons icons,
    required FTypography typography,
    required FStyle style,
    required bool touch,
  }) {
    final inherited = FSelectStyle.inherit(
      colors: colors,
      icons: icons,
      typography: typography,
      style: style,
      touch: touch,
    );
    final sectionStyle = _selectSectionStyle(
      colors: colors,
      typography: typography,
      style: style,
      touch: touch,
      hoverColor: colors.accentColors.accent,
    );

    return FSelectStyle(
      fieldStyles: inherited.fieldStyles,
      searchStyle: inherited.searchStyle,
      contentStyle: FSelectContentStyle(
        sectionStyle: sectionStyle,
        scrollHandleStyle: inherited.contentStyle.scrollHandleStyle,
        padding: inherited.contentStyle.padding,
        decoration: inherited.contentStyle.decoration,
        barrierFilter: inherited.contentStyle.barrierFilter,
        backgroundFilter: inherited.contentStyle.backgroundFilter,
        popoverPadding: inherited.contentStyle.popoverPadding,
        motion: inherited.contentStyle.motion,
      ),
      emptyTextStyle: inherited.emptyTextStyle,
    );
  }

  static FMultiSelectStyle multiSelectStyle({
    required FColors colors,
    required FIcons icons,
    required FTypography typography,
    required FStyle style,
    required bool touch,
  }) {
    final inherited = FMultiSelectStyle.inherit(
      colors: colors,
      icons: icons,
      typography: typography,
      style: style,
      touch: touch,
    );
    final sectionStyle = _selectSectionStyle(
      colors: colors,
      typography: typography,
      style: style,
      touch: touch,
      hoverColor: colors.accentColors.accent,
    );

    return FMultiSelectStyle(
      fieldStyles: inherited.fieldStyles,
      searchStyle: inherited.searchStyle,
      contentStyle: FSelectContentStyle(
        sectionStyle: sectionStyle,
        scrollHandleStyle: inherited.contentStyle.scrollHandleStyle,
        padding: inherited.contentStyle.padding,
        decoration: inherited.contentStyle.decoration,
        barrierFilter: inherited.contentStyle.barrierFilter,
        backgroundFilter: inherited.contentStyle.backgroundFilter,
        popoverPadding: inherited.contentStyle.popoverPadding,
        motion: inherited.contentStyle.motion,
      ),
      emptyTextStyle: inherited.emptyTextStyle,
    );
  }

  static FAutocompleteStyle autocompleteStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required bool touch,
  }) {
    final inherited = FAutocompleteStyle.inherit(colors: colors, typography: typography, style: style, touch: touch);
    final sectionStyle = _autocompleteSectionStyle(
      colors: colors,
      typography: typography,
      style: style,
      touch: touch,
      hoverColor: colors.accentColors.accent,
    );

    return FAutocompleteStyle(
      fieldStyles: inherited.fieldStyles,
      contentStyle: FAutocompleteContentStyle(
        emptyTextStyle: inherited.contentStyle.emptyTextStyle,
        progressStyle: inherited.contentStyle.progressStyle,
        sectionStyle: sectionStyle,
        decoration: inherited.contentStyle.decoration,
        padding: inherited.contentStyle.padding,
        barrierFilter: inherited.contentStyle.barrierFilter,
        backgroundFilter: inherited.contentStyle.backgroundFilter,
        popoverPadding: inherited.contentStyle.popoverPadding,
        motion: inherited.contentStyle.motion,
      ),
    );
  }

  static FButtonSizeStyles _outlineButtonSizeStyles({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required bool touch,
    required Color accent,
  }) {
    return FButtonSizeStyles.inherit(
      typography: typography,
      style: style,
      touch: touch,
      foregroundColor: colors.foreground,
      disabledForegroundColor: colors.disable(colors.foreground),
      decoration: (radius) => FVariants.from(
        ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            side: BorderSide(color: colors.border, width: style.borderWidth),
            borderRadius: radius,
          ),
          color: colors.card,
        ),
        variants: {
          [FTappableVariant.hovered, FTappableVariant.pressed]: DecorationDelta.shapeDelta(color: accent),
          [FTappableVariant.disabled]: DecorationDelta.shapeDelta(color: colors.disable(colors.card)),
          [FTappableVariant.selected]: DecorationDelta.shapeDelta(color: accent),
          [FTappableVariant.selected.and(FTappableVariant.disabled)]: DecorationDelta.shapeDelta(
            color: colors.disable(accent),
          ),
        },
      ),
    );
  }

  static FButtonSizeStyles _ghostButtonSizeStyles({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required bool touch,
    required Color accent,
  }) {
    return FButtonSizeStyles.inherit(
      typography: typography,
      style: style,
      touch: touch,
      foregroundColor: colors.foreground,
      disabledForegroundColor: colors.disable(colors.foreground),
      decoration: (radius) => FVariants.from(
        ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius)),
        variants: {
          [FTappableVariant.hovered, FTappableVariant.pressed]: DecorationDelta.shapeDelta(color: accent),
          [FTappableVariant.disabled]: const DecorationDelta.shapeDelta(),
          [FTappableVariant.selected]: DecorationDelta.shapeDelta(color: accent),
          [FTappableVariant.selected.and(FTappableVariant.disabled)]: DecorationDelta.shapeDelta(
            color: colors.disable(accent),
          ),
        },
      ),
    );
  }

  static FItemStyle _interactiveItemStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required bool touch,
    required Color hoverColor,
    required Color backgroundColor,
  }) {
    return FItemStyle(
      backgroundColor: FVariants(
        backgroundColor,
        variants: {
          [FTappableVariant.disabled]: backgroundColor,
        },
      ),
      contentDecoration: FVariants.from(
        ShapeDecoration(
          shape: RoundedSuperellipseBorder(borderRadius: style.borderRadius.md),
          color: backgroundColor,
        ),
        variants: {
          [FTappableVariant.hovered, FTappableVariant.pressed]: DecorationDelta.shapeDelta(color: hoverColor),
          [FTappableVariant.disabled]: const DecorationDelta.shapeDelta(),
          [FTappableVariant.selected]: DecorationDelta.shapeDelta(color: hoverColor),
          [FTappableVariant.selected.and(FTappableVariant.disabled)]: DecorationDelta.shapeDelta(
            color: colors.disable(hoverColor),
          ),
        },
      ),
      contentStyle: FItemContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.primary,
        foreground: colors.foreground,
        mutedForeground: colors.mutedForeground,
        touch: touch,
      ),
      rawContentStyle: FRawItemContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.foreground,
        color: colors.foreground,
        touch: touch,
      ),
      tappableStyle: style.tappableStyle.copyWith(
        motion: FTappableMotion.none,
        pressedEnterDuration: Duration.zero,
        pressedExitDuration: const Duration(milliseconds: 25),
      ),
      focusedOutlineStyle: style.focusedOutlineStyle,
    );
  }

  static FTileStyles _tileGroupTileStyles({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
  }) {
    final accent = colors.accentColors.accent;
    final primary = _groupTileStyle(colors: colors, typography: typography, style: style, hoverColor: accent);

    return FTileStyles(
      FVariants.from(
        primary,
        variants: {
          [FItemVariant.destructive]: _destructiveTileDelta(colors: colors, typography: typography),
        },
      ),
    );
  }

  static FItemGroupStyle _popoverMenuItemGroupStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required FHapticFeedback hapticFeedback,
    required bool touch,
  }) {
    final accent = colors.accentColors.accent;
    final inherited = FItemGroupStyle.inherit(
      colors: colors,
      typography: typography,
      style: style,
      hapticFeedback: hapticFeedback,
      touch: touch,
    );
    final itemStyle = _popoverMenuItemStyle(
      colors: colors,
      typography: typography,
      style: style,
      touch: touch,
      hoverColor: accent,
    );

    return FItemGroupStyle(
      decoration: ShapeDecoration(
        color: colors.card,
        shape: RoundedSuperellipseBorder(
          side: BorderSide(color: colors.border, width: style.borderWidth),
          borderRadius: style.borderRadius.md,
        ),
      ),
      dividerColor: inherited.dividerColor,
      dividerWidth: inherited.dividerWidth,
      itemStyles: FItemStyles(
        FVariants.from(
          itemStyle,
          variants: {
            [FItemVariant.destructive]: _destructiveItemDelta(colors: colors, typography: typography, touch: touch),
          },
        ),
      ),
      slideableItems: inherited.slideableItems,
      slidePressHapticFeedback: inherited.slidePressHapticFeedback,
      spacing: inherited.spacing,
    );
  }

  static FTileStyle _groupTileStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required Color hoverColor,
  }) {
    return FTileStyle(
      backgroundColor: FVariants.all(colors.card),
      contentDecoration: FVariants.from(
        ShapeDecoration(
          shape: RoundedSuperellipseBorder(borderRadius: style.borderRadius.md),
          color: colors.card,
        ),
        variants: {
          [FTappableVariant.hovered, FTappableVariant.pressed]: DecorationDelta.shapeDelta(color: hoverColor),
          [FTappableVariant.disabled]: DecorationDelta.shapeDelta(color: colors.disable(hoverColor)),
        },
      ),
      contentStyle: FTileContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.primary,
        foreground: colors.foreground,
        mutedForeground: colors.mutedForeground,
      ),
      rawContentStyle: FRawTileContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.primary,
        color: colors.foreground,
      ),
      tappableStyle: style.tappableStyle.copyWith(
        motion: FTappableMotion.none,
        pressedEnterDuration: Duration.zero,
        pressedExitDuration: const Duration(milliseconds: 25),
      ),
      focusedOutlineStyle: style.focusedOutlineStyle.copyWith(spacing: -style.borderWidth * 2),
      shape: RoundedSuperellipseBorder(borderRadius: style.borderRadius.md),
    );
  }

  static FTileStyle _tileStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required Color hoverColor,
  }) {
    return FTileStyle(
      backgroundColor: FVariants.all(colors.card),
      contentDecoration: FVariants.from(
        ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            side: BorderSide(color: colors.border, width: style.borderWidth),
            borderRadius: style.borderRadius.md,
          ),
          color: colors.card,
        ),
        variants: {
          [FTappableVariant.hovered, FTappableVariant.pressed]: DecorationDelta.shapeDelta(color: hoverColor),
          [FTappableVariant.disabled]: DecorationDelta.shapeDelta(color: colors.disable(hoverColor)),
        },
      ),
      contentStyle: FTileContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.primary,
        foreground: colors.foreground,
        mutedForeground: colors.mutedForeground,
      ),
      rawContentStyle: FRawTileContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.primary,
        color: colors.foreground,
      ),
      tappableStyle: style.tappableStyle.copyWith(
        motion: FTappableMotion.none,
        pressedEnterDuration: Duration.zero,
        pressedExitDuration: const Duration(milliseconds: 25),
      ),
      focusedOutlineStyle: style.focusedOutlineStyle.copyWith(spacing: -style.borderWidth * 2),
      shape: RoundedSuperellipseBorder(borderRadius: style.borderRadius.md),
    );
  }

  static FSelectSectionStyle _selectSectionStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required bool touch,
    required Color hoverColor,
  }) {
    return FSelectSectionStyle(
      labelTextStyle: FVariants.from(
        typography.xs.copyWith(color: colors.mutedForeground),
        variants: {
          [.disabled]: .delta(color: colors.disable(colors.mutedForeground)),
        },
      ),
      dividerColor: FVariants.all(colors.border),
      dividerWidth: style.borderWidth,
      itemStyle: _menuItemStyle(
        colors: colors,
        typography: typography,
        style: style,
        touch: touch,
        hoverColor: hoverColor,
      ),
    );
  }

  static FAutocompleteSectionStyle _autocompleteSectionStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required bool touch,
    required Color hoverColor,
  }) {
    return FAutocompleteSectionStyle(
      labelTextStyle: FVariants.from(
        typography.xs.copyWith(color: colors.mutedForeground),
        variants: {
          [.disabled]: .delta(color: colors.disable(colors.mutedForeground)),
        },
      ),
      dividerColor: FVariants.all(colors.border),
      dividerWidth: style.borderWidth,
      itemStyle: _menuItemStyle(
        colors: colors,
        typography: typography,
        style: style,
        touch: touch,
        hoverColor: hoverColor,
      ),
    );
  }

  static FItemStyle _popoverMenuItemStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required bool touch,
    required Color hoverColor,
  }) {
    return FItemStyle(
      backgroundColor: FVariants.all(colors.card),
      contentDecoration: FVariants.from(
        ShapeDecoration(
          shape: RoundedSuperellipseBorder(borderRadius: style.borderRadius.md),
          color: colors.card,
        ),
        variants: {
          [FTappableVariant.focused, FTappableVariant.hovered, FTappableVariant.pressed]: DecorationDelta.shapeDelta(
            shape: RoundedSuperellipseBorder(borderRadius: style.borderRadius.md),
            color: hoverColor,
          ),
          [FTappableVariant.disabled]: const DecorationDelta.shapeDelta(),
        },
      ),
      contentStyle: FItemContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.foreground,
        foreground: colors.foreground,
        mutedForeground: colors.mutedForeground,
        touch: touch,
      ),
      rawContentStyle: FRawItemContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.foreground,
        color: colors.foreground,
        touch: touch,
      ),
      tappableStyle: style.tappableStyle.copyWith(motion: FTappableMotion.none),
      focusedOutlineStyle: null,
    );
  }

  static FItemStyleDelta _destructiveItemDelta({
    required FColors colors,
    required FTypography typography,
    required bool touch,
  }) {
    return FItemStyleDelta.delta(
      contentStyle: FItemContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.destructive,
        foreground: colors.destructive,
        mutedForeground: colors.destructive,
        touch: touch,
      ),
      rawContentStyle: FRawItemContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.destructive,
        color: colors.destructive,
        touch: touch,
      ),
    );
  }

  static FTileStyleDelta _destructiveTileDelta({required FColors colors, required FTypography typography}) {
    return FTileStyleDelta.delta(
      contentStyle: FTileContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.destructive,
        foreground: colors.destructive,
        mutedForeground: colors.destructive,
      ),
      rawContentStyle: FRawTileContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.destructive,
        color: colors.destructive,
      ),
    );
  }

  static FItemStyle _menuItemStyle({
    required FColors colors,
    required FTypography typography,
    required FStyle style,
    required bool touch,
    required Color hoverColor,
  }) {
    return FItemStyle(
      backgroundColor: const FVariants.all(null),
      contentDecoration: FVariants.from(
        const ShapeDecoration(shape: RoundedSuperellipseBorder()),
        variants: {
          [FTappableVariant.focused, FTappableVariant.hovered, FTappableVariant.pressed]: DecorationDelta.shapeDelta(
            shape: RoundedSuperellipseBorder(borderRadius: style.borderRadius.md),
            color: hoverColor,
          ),
          [FTappableVariant.disabled]: const DecorationDelta.shapeDelta(),
        },
      ),
      contentStyle: FItemContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.foreground,
        foreground: colors.foreground,
        mutedForeground: colors.mutedForeground,
        touch: touch,
      ),
      rawContentStyle: FRawItemContentStyle.inherit(
        colors: colors,
        typography: typography,
        prefix: colors.foreground,
        color: colors.foreground,
        touch: touch,
      ),
      tappableStyle: style.tappableStyle.copyWith(motion: FTappableMotion.none),
      focusedOutlineStyle: null,
    );
  }
}
