import 'package:flutter/material.dart';

import 'app_theme_meta.dart';
import 'color_tokens.dart';
import 'semantic_colors.dart';
import 'shadow_tokens.dart';
import 'spacing_tokens.dart';
import 'variants/app_theme_variant.dart';
import 'variants/theme_palette_resolver.dart';

/// Builds [ThemeData] from a named design-system variant.
class AppTheme {
  const AppTheme._();

  static ThemeData light([AppThemeVariant variant = AppThemeVariant.clinic]) => _build(variant, Brightness.light);

  static ThemeData dark([AppThemeVariant variant = AppThemeVariant.clinic]) => _build(variant, Brightness.dark);

  static ThemeData _build(AppThemeVariant variant, Brightness brightness) {
    final tokens = ThemePaletteResolver.colors(variant, brightness);
    final shapes = ThemePaletteResolver.shapes(variant);
    final semantic = SemanticColors.fromTokens(tokens);
    final colorScheme = _colorScheme(tokens, brightness);
    final borderRadius = BorderRadius.circular(shapes.lg);
    final textTheme = ThemePaletteResolver.typography(
      variant,
      foreground: tokens.foreground,
      mutedForeground: tokens.mutedForeground,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.background,
      textTheme: textTheme,
      extensions: [
        semantic,
        shapes,
        AppThemeMeta(variant: variant),
      ],
      dividerColor: tokens.border,
      splashColor: tokens.primary.withValues(alpha: 0.08),
      highlightColor: tokens.primary.withValues(alpha: 0.04),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.background,
        foregroundColor: tokens.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: tokens.card,
        elevation: 0,
        shadowColor: ShadowTokens.shadowColor,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: tokens.border),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.popover,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.popover,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(shapes.xl))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.input,
        contentPadding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapes.md),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapes.md),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapes.md),
          borderSide: BorderSide(color: tokens.ring, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapes.md),
          borderSide: BorderSide(color: tokens.destructive),
        ),
        hintStyle: TextStyle(color: tokens.mutedForeground),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: tokens.primaryForeground,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: tokens.primaryForeground,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.foreground,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: 14),
          side: BorderSide(color: tokens.border),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.primary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.muted,
        labelStyle: TextStyle(color: tokens.foreground),
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(shapes.md)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tokens.foreground,
        contentTextStyle: TextStyle(color: tokens.background),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(shapes.md)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: tokens.primary),
      dividerTheme: DividerThemeData(color: tokens.border, space: SpacingTokens.lg),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: tokens.foreground),
        dataTextStyle: TextStyle(color: tokens.foreground),
        dividerThickness: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.sidebar,
        indicatorColor: tokens.sidebarAccent,
        selectedIconTheme: IconThemeData(color: tokens.sidebarPrimary),
        selectedLabelTextStyle: TextStyle(color: tokens.sidebarPrimary),
        unselectedIconTheme: IconThemeData(color: tokens.sidebarForeground),
        unselectedLabelTextStyle: TextStyle(color: tokens.sidebarForeground),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.primary;
          }
          return null;
        }),
        side: BorderSide(color: tokens.border),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.primary;
          }
          return tokens.mutedForeground;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.primaryForeground;
          }
          return tokens.background;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.primary;
          }
          return tokens.muted;
        }),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.popover,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(shapes.sm),
          boxShadow: ShadowTokens.shadowSm,
        ),
        textStyle: TextStyle(color: tokens.popoverForeground),
      ),
    );
  }

  static ColorScheme _colorScheme(ColorTokens tokens, Brightness brightness) {
    return ColorScheme(
      brightness: brightness,
      primary: tokens.primary,
      onPrimary: tokens.primaryForeground,
      secondary: tokens.secondary,
      onSecondary: tokens.secondaryForeground,
      error: tokens.destructive,
      onError: tokens.destructiveForeground,
      surface: tokens.background,
      onSurface: tokens.foreground,
      surfaceContainerHighest: tokens.muted,
      onSurfaceVariant: tokens.mutedForeground,
      outline: tokens.border,
      outlineVariant: tokens.border,
      tertiary: tokens.accent,
      onTertiary: tokens.accentForeground,
      tertiaryContainer: tokens.accent,
      onTertiaryContainer: tokens.accentForeground,
    );
  }
}
