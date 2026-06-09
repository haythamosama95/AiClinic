import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'color_tokens.dart';
import 'forui_accent_colors.dart';
import 'forui_style_overrides.dart';
import 'variants/app_theme_variant.dart';
import 'variants/theme_palette_resolver.dart';

/// Builds [FThemeData] from a named design-system variant for the desktop client.
abstract final class ForuiTheme {
  static FThemeData dataFor(Brightness brightness, {AppThemeVariant variant = AppThemeVariant.clinic}) {
    final tokens = ThemePaletteResolver.colors(variant, brightness);
    final colors = _colorsFromTokens(tokens, brightness);
    final typography = FTypography.inherit(colors: colors, touch: false);
    final icons = FIcons.lucide();
    final style = FStyle.inherit(colors: colors, typography: typography, touch: false);

    return FThemeData(
      touch: false,
      debugLabel: '${variant.name} ${brightness == Brightness.dark ? 'dark' : 'light'} desktop',
      colors: colors,
      typography: typography,
      icons: icons,
      style: style,
      buttonStyles: ForuiStyleOverrides.buttonStyles(
        colors: colors,
        typography: typography,
        style: style,
        touch: false,
      ),
      itemStyles: ForuiStyleOverrides.itemStyles(colors: colors, typography: typography, style: style, touch: false),
      itemGroupStyle: ForuiStyleOverrides.itemGroupStyle(
        colors: colors,
        typography: typography,
        style: style,
        hapticFeedback: const FHapticFeedback(),
        touch: false,
      ),
      tileStyles: ForuiStyleOverrides.tileStyles(colors: colors, typography: typography, style: style),
      tileGroupStyle: ForuiStyleOverrides.tileGroupStyle(
        colors: colors,
        typography: typography,
        style: style,
        hapticFeedback: const FHapticFeedback(),
      ),
      popoverMenuStyle: ForuiStyleOverrides.popoverMenuStyle(
        colors: colors,
        typography: typography,
        style: style,
        hapticFeedback: const FHapticFeedback(),
        touch: false,
      ),
      selectStyle: ForuiStyleOverrides.selectStyle(
        colors: colors,
        icons: icons,
        typography: typography,
        style: style,
        touch: false,
      ),
      multiSelectStyle: ForuiStyleOverrides.multiSelectStyle(
        colors: colors,
        icons: icons,
        typography: typography,
        style: style,
        touch: false,
      ),
      autocompleteStyle: ForuiStyleOverrides.autocompleteStyle(
        colors: colors,
        typography: typography,
        style: style,
        touch: false,
      ),
    );
  }

  static FColors _colorsFromTokens(ColorTokens tokens, Brightness brightness) {
    final template = brightness == Brightness.dark ? FColors.neutralDark : FColors.neutralLight;
    final accent = FAccentColors.fromTokens(tokens);

    return template.copyWith(
      background: tokens.background,
      foreground: tokens.foreground,
      primary: tokens.primary,
      primaryForeground: tokens.primaryForeground,
      secondary: tokens.secondary,
      secondaryForeground: tokens.secondaryForeground,
      muted: tokens.muted,
      mutedForeground: tokens.mutedForeground,
      destructive: tokens.destructive,
      destructiveForeground: tokens.destructiveForeground,
      error: tokens.destructive,
      errorForeground: tokens.destructiveForeground,
      card: tokens.card,
      border: tokens.border,
      extensions: [accent],
    );
  }
}
