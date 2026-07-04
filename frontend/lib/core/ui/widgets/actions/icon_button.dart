import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

enum AppIconButtonVariant { ghost, secondary, danger, ai }

enum AppIconButtonSize { sm, md, lg }

@immutable
class _IconButtonPalette {
  const _IconButtonPalette({
    required this.background,
    required this.foreground,
    required this.border,
    required this.hoverBackground,
    required this.activeBackground,
    required this.focusRing,
  });

  final Color background;
  final Color foreground;
  final Color? border;
  final Color hoverBackground;
  final Color activeBackground;
  final Color focusRing;

  static _IconButtonPalette resolve({
    required AppColors colors,
    required AppIconButtonVariant variant,
    required bool disabled,
  }) {
    if (disabled) {
      return _IconButtonPalette(
        background: colors.actionDisabledBg,
        foreground: colors.textDisabled,
        border: null,
        hoverBackground: colors.actionDisabledBg,
        activeBackground: colors.actionDisabledBg,
        focusRing: colors.focusRing,
      );
    }

    return switch (variant) {
      AppIconButtonVariant.ghost => _IconButtonPalette(
        background: Colors.transparent,
        foreground: colors.iconDefault,
        border: null,
        hoverBackground: colors.actionSubtleHover,
        activeBackground: colors.surfaceMuted,
        focusRing: colors.focusRing,
      ),
      AppIconButtonVariant.secondary => _IconButtonPalette(
        background: colors.actionSecondary,
        foreground: colors.iconDefault,
        border: colors.borderDefault,
        hoverBackground: colors.surfaceHover,
        activeBackground: colors.surfaceMuted,
        focusRing: colors.focusRing,
      ),
      AppIconButtonVariant.danger => _IconButtonPalette(
        background: Colors.transparent,
        foreground: colors.statusDangerFg,
        border: null,
        hoverBackground: colors.statusDangerSurface,
        activeBackground: colors.statusDangerSurface,
        focusRing: colors.focusRing,
      ),
      AppIconButtonVariant.ai => _IconButtonPalette(
        background: Colors.transparent,
        foreground: colors.textAi,
        border: null,
        hoverBackground: colors.surfaceAi,
        activeBackground: colors.surfaceAi,
        focusRing: colors.focusRingAi,
      ),
    };
  }
}

/// Icon-only button with required accessible label.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onPressed,
    this.variant = AppIconButtonVariant.ghost,
    this.size = AppIconButtonSize.md,
    this.error = false,
    this.disabled = false,
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;
  final AppIconButtonSize size;
  final bool error;
  final bool disabled;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? tooltip;

  double get _dimension => switch (size) {
    AppIconButtonSize.sm => 28,
    AppIconButtonSize.md => 32,
    AppIconButtonSize.lg => 40,
  };

  double get _iconSize => switch (size) {
    AppIconButtonSize.sm => 16,
    AppIconButtonSize.md => 20,
    AppIconButtonSize.lg => 24,
  };

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  FocusNode? _focusNode;
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _focusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _focusNode = FocusNode();
    }
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = _IconButtonPalette.resolve(
      colors: colors,
      variant: widget.variant,
      disabled: widget.disabled,
    );
    final reducedMotion = AppMotion.isReducedMotion(context);
    final dimension = widget._dimension;

    Color background = palette.background;
    Color foreground = palette.foreground;
    if (!widget.disabled) {
      if (_pressed) {
        background = palette.activeBackground;
      } else if (_hovered) {
        background = palette.hoverBackground;
        if (widget.variant == AppIconButtonVariant.ghost ||
            widget.variant == AppIconButtonVariant.secondary) {
          foreground = colors.textPrimary;
        }
      }
    }

    final ringColor = widget.error && !widget.disabled
        ? colors.statusDangerBorder
        : (_focused ? palette.focusRing : Colors.transparent);

    Widget button = Semantics(
      button: true,
      label: widget.semanticLabel,
      enabled: !widget.disabled,
      child: Focus(
        focusNode: _effectiveFocusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (widget.disabled) return KeyEventResult.ignored;
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onPressed?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: widget.disabled
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.disabled
                ? null
                : (_) => setState(() => _pressed = true),
            onTapUp: widget.disabled
                ? null
                : (_) => setState(() => _pressed = false),
            onTapCancel: widget.disabled
                ? null
                : () => setState(() => _pressed = false),
            onTap: widget.disabled ? null : widget.onPressed,
            child: Container(
              padding: ringColor == Colors.transparent
                  ? EdgeInsets.zero
                  : const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: AppRadius.mdAll,
                border: ringColor == Colors.transparent
                    ? null
                    : Border.all(color: ringColor, width: 2),
              ),
              child: AnimatedScale(
                scale: _pressed && !widget.disabled && !reducedMotion
                    ? AppMotion.buttonPressScale
                    : 1,
                duration: AppDurations.instant,
                curve: AppCurves.standard,
                child: AnimatedContainer(
                  duration: AppDurations.instant,
                  curve: AppCurves.standard,
                  width: dimension,
                  height: dimension,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: AppRadius.mdAll,
                    border: palette.border == null
                        ? null
                        : Border.all(color: palette.border!),
                  ),
                  child: Icon(
                    widget.icon,
                    size: widget._iconSize,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final tooltip = widget.tooltip ?? widget.semanticLabel;
    if (widget.disabled || tooltip.isEmpty) {
      return button;
    }

    return Tooltip(message: tooltip, child: button);
  }
}
