import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// Application-owned icon button (`04-components` A2).
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.variant = AppIconButtonVariant.ghost,
    this.size = AppIconButtonSize.md,
    this.dimension,
    this.error = false,
    this.tooltip,
    this.tooltipDisabled = false,
    super.key,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;
  final AppIconButtonSize size;

  /// When set, overrides [AppIconButtonSize.dimension] (e.g. to match an input field height).
  final double? dimension;
  final bool error;
  final String? tooltip;
  final bool tooltipDisabled;

  bool get disabled => onPressed == null;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  double get _dimension => widget.dimension ?? widget.size.dimension;

  double get _iconSize => widget.size == AppIconButtonSize.lg ? 20 : 16;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = _resolveStyle(colors, isDark);
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final scale = !widget.disabled && _pressed && !reducedMotion ? 0.98 : 1.0;

    Widget button = Semantics(
      label: widget.label,
      button: true,
      enabled: !widget.disabled,
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          cursor: widget.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.disabled ? null : (_) => setState(() => _pressed = true),
            onTapUp: widget.disabled ? null : (_) => setState(() => _pressed = false),
            onTapCancel: widget.disabled ? null : () => setState(() => _pressed = false),
            onTap: widget.onPressed,
            child: AnimatedScale(
              scale: scale,
              duration: AppMotion.instant,
              curve: AppMotion.standardCurve,
              child: _buildButtonSurface(colors, isDark, style),
            ),
          ),
        ),
      ),
    );

    if (!widget.tooltipDisabled && !widget.disabled) {
      button = Tooltip(message: widget.tooltip ?? widget.label, child: button);
    }

    return button;
  }

  Widget _buildButtonSurface(AppSemanticColors colors, bool isDark, _IconButtonStyle style) {
    final radius = BorderRadius.circular(AppRadius.md);
    final focusRingColor = widget.variant == AppIconButtonVariant.ai
        ? (isDark ? AppColorPrimitives.focusRingAiDark : AppColorPrimitives.focusRingAiLight)
        : (isDark ? AppColorPrimitives.focusRingDark : AppColorPrimitives.focusRingLight);

    Widget core = Container(
      width: _dimension,
      height: _dimension,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: radius,
        border: style.borderColor == null ? null : Border.all(color: style.borderColor!),
        boxShadow: _focused && !widget.disabled
            ? [BoxShadow(color: focusRingColor, blurRadius: 0, spreadRadius: 2)]
            : null,
      ),
      child: IconTheme(
        data: IconThemeData(size: _iconSize, color: style.foreground),
        child: widget.icon,
      ),
    );

    if (widget.error && !widget.disabled) {
      final dangerBorder = isDark ? AppColorPrimitives.statusDangerBorderDark : AppColorPrimitives.red100;
      core = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          borderRadius: BorderRadius.circular(AppRadius.md + 2),
          border: Border.all(color: dangerBorder, width: 2),
        ),
        child: core,
      );
    }

    return core;
  }

  _IconButtonStyle _resolveStyle(AppSemanticColors colors, bool isDark) {
    if (widget.disabled) {
      return _IconButtonStyle(
        background: isDark ? AppColorPrimitives.actionDisabledBgDark : AppColorPrimitives.neutral100,
        foreground: isDark ? AppColorPrimitives.textDisabledDark : AppColorPrimitives.neutral400,
      );
    }

    final secondaryBackground = isDark ? AppColorPrimitives.surfaceRaisedDark : colors.surfaceDefault;
    final subtleHover = isDark ? AppColorPrimitives.surfaceHoverDark : AppColorPrimitives.neutral50;

    return switch (widget.variant) {
      AppIconButtonVariant.ghost => _IconButtonStyle(
        background: _pressed
            ? colors.surfaceMuted
            : _hovered
            ? subtleHover
            : Colors.transparent,
        foreground: _hovered ? colors.textPrimary : colors.iconDefault,
      ),
      AppIconButtonVariant.secondary => _IconButtonStyle(
        background: _pressed
            ? colors.surfaceMuted
            : _hovered
            ? colors.surfaceHover
            : secondaryBackground,
        foreground: _hovered ? colors.textPrimary : colors.iconDefault,
        borderColor: colors.borderDefault,
      ),
      AppIconButtonVariant.primary => _IconButtonStyle(
        background: _pressed
            ? colors.actionPrimaryActive
            : _hovered
            ? colors.actionPrimaryHover
            : colors.actionPrimary,
        foreground: colors.actionPrimaryFg,
      ),
      AppIconButtonVariant.danger => _IconButtonStyle(
        background: _pressed
            ? (isDark ? AppColorPrimitives.statusDangerBorderDark : AppColorPrimitives.red100)
            : _hovered
            ? (isDark
                  ? AppColorPrimitives.statusDangerBorderDark.withValues(alpha: 0.35)
                  : AppColorPrimitives.red100.withValues(alpha: 0.7))
            : colors.statusDangerSurface,
        foreground: colors.statusDangerFg,
      ),
      AppIconButtonVariant.ai => _IconButtonStyle(
        background: _pressed || _hovered ? colors.surfaceAi : Colors.transparent,
        foreground: colors.textAi,
      ),
    };
  }
}

class _IconButtonStyle {
  const _IconButtonStyle({required this.background, required this.foreground, this.borderColor});

  final Color background;
  final Color foreground;
  final Color? borderColor;
}

enum AppIconButtonVariant { primary, ghost, secondary, danger, ai }

enum AppIconButtonSize { sm, md, lg }

extension AppIconButtonSizeDimension on AppIconButtonSize {
  double get dimension => switch (this) {
    AppIconButtonSize.sm => 28,
    AppIconButtonSize.md => 32,
    AppIconButtonSize.lg => 40,
  };
}
