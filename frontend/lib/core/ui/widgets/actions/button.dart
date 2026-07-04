import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/spinner.dart';

enum AppButtonVariant { primary, secondary, ghost, danger, ai, link }

enum AppButtonSize { sm, md, lg }

/// Resolved visual tokens for [AppButton] and split-button triggers.
@immutable
class AppButtonMetrics {
  const AppButtonMetrics({
    required this.height,
    required this.minWidth,
    required this.horizontalPadding,
    required this.gap,
    required this.iconSize,
    required this.textStyle,
    required this.spinnerSize,
  });

  final double height;
  final double minWidth;
  final double horizontalPadding;
  final double gap;
  final double iconSize;
  final TextStyle textStyle;
  final AppSpinnerSize spinnerSize;

  static AppButtonMetrics forSize(
    AppButtonSize size,
    AppTypography typography,
  ) {
    return switch (size) {
      AppButtonSize.sm => AppButtonMetrics(
        height: 28,
        minWidth: 72,
        horizontalPadding: AppSpacing.s2,
        gap: 6,
        iconSize: 16,
        textStyle: typography.bodySm,
        spinnerSize: AppSpinnerSize.sm,
      ),
      AppButtonSize.md => AppButtonMetrics(
        height: 36,
        minWidth: 88,
        horizontalPadding: AppSpacing.s3,
        gap: AppSpacing.s2,
        iconSize: 16,
        textStyle: typography.bodyStrong,
        spinnerSize: AppSpinnerSize.sm,
      ),
      AppButtonSize.lg => AppButtonMetrics(
        height: 44,
        minWidth: 104,
        horizontalPadding: AppSpacing.s4,
        gap: AppSpacing.s2,
        iconSize: 20,
        textStyle: typography.bodyStrong,
        spinnerSize: AppSpinnerSize.md,
      ),
    };
  }
}

@immutable
class AppButtonColors {
  const AppButtonColors({
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

  static AppButtonColors resolve({
    required AppColors colors,
    required AppButtonVariant variant,
    required bool disabled,
  }) {
    if (disabled) {
      return AppButtonColors(
        background: variant == AppButtonVariant.link
            ? Colors.transparent
            : colors.actionDisabledBg,
        foreground: colors.textDisabled,
        border: null,
        hoverBackground: colors.actionDisabledBg,
        activeBackground: colors.actionDisabledBg,
        focusRing: colors.focusRing,
      );
    }

    return switch (variant) {
      AppButtonVariant.primary => AppButtonColors(
        background: colors.actionPrimary,
        foreground: colors.actionPrimaryFg,
        border: null,
        hoverBackground: colors.actionPrimaryHover,
        activeBackground: colors.actionPrimaryActive,
        focusRing: colors.focusRing,
      ),
      AppButtonVariant.secondary => AppButtonColors(
        background: colors.actionSecondary,
        foreground: colors.actionSecondaryFg,
        border: colors.borderDefault,
        hoverBackground: colors.surfaceHover,
        activeBackground: colors.surfaceMuted,
        focusRing: colors.focusRing,
      ),
      AppButtonVariant.ghost => AppButtonColors(
        background: Colors.transparent,
        foreground: colors.textPrimary,
        border: null,
        hoverBackground: colors.actionSubtleHover,
        activeBackground: colors.surfaceMuted,
        focusRing: colors.focusRing,
      ),
      AppButtonVariant.danger => AppButtonColors(
        background: colors.actionDanger,
        foreground: colors.actionDangerFg,
        border: null,
        hoverBackground: colors.actionDangerHover,
        activeBackground: colors.actionDangerActive,
        focusRing: colors.focusRing,
      ),
      AppButtonVariant.ai => AppButtonColors(
        background: colors.actionAi,
        foreground: colors.actionAiFg,
        border: null,
        hoverBackground: colors.actionAiHover,
        activeBackground: colors.actionAi,
        focusRing: colors.focusRingAi,
      ),
      AppButtonVariant.link => AppButtonColors(
        background: Colors.transparent,
        foreground: colors.textLink,
        border: null,
        hoverBackground: Colors.transparent,
        activeBackground: Colors.transparent,
        focusRing: colors.focusRing,
      ),
    };
  }
}

/// Primary action button matching the web `Button` component.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.loading = false,
    this.error = false,
    this.disabled = false,
    this.leadingIcon,
    this.trailingIcon,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.borderRadius,
    this.clipLeadingRadius = true,
    this.clipTrailingRadius = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool error;
  final bool disabled;
  final Object? leadingIcon;
  final Object? trailingIcon;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final BorderRadius? borderRadius;
  final bool clipLeadingRadius;
  final bool clipTrailingRadius;

  bool get isDisabled => disabled || loading;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  final GlobalKey _measureKey = GlobalKey();
  FocusNode? _focusNode;
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  double? _lockedMinWidth;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _focusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _focusNode = FocusNode();
    }
  }

  @override
  void didUpdateWidget(AppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading && !oldWidget.loading) {
      _captureWidth();
    } else if (!widget.loading && oldWidget.loading) {
      _lockedMinWidth = null;
    }
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    super.dispose();
  }

  void _captureWidth() {
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      _lockedMinWidth = box.size.width;
    }
  }

  Widget? _buildIcon(Object? icon, double size, Color color) {
    if (icon == null) return null;
    if (icon is IconData) {
      return Icon(icon, size: size, color: color);
    }
    if (icon is Widget) {
      return IconTheme(
        data: IconThemeData(size: size, color: color),
        child: icon,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final metrics = AppButtonMetrics.forSize(widget.size, typography);
    final palette = AppButtonColors.resolve(
      colors: colors,
      variant: widget.variant,
      disabled: widget.isDisabled,
    );
    final reducedMotion = AppMotion.isReducedMotion(context);
    final isLink = widget.variant == AppButtonVariant.link;
    final borderRadius = widget.borderRadius ?? AppRadius.mdAll;

    Color background = palette.background;
    if (!widget.isDisabled) {
      if (_pressed) {
        background = palette.activeBackground;
      } else if (_hovered) {
        background = palette.hoverBackground;
      }
    }

    final foreground = palette.foreground;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          AppSpinner(size: metrics.spinnerSize)
        else ...[
          if (widget.leadingIcon != null) ...[
            _buildIcon(widget.leadingIcon, metrics.iconSize, foreground)!,
            SizedBox(width: metrics.gap),
          ],
          DefaultTextStyle(
            style: metrics.textStyle.copyWith(
              color: foreground,
              decoration: isLink && _hovered && !widget.isDisabled
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: foreground,
            ),
            child: widget.child,
          ),
          if (widget.trailingIcon != null) ...[
            SizedBox(width: metrics.gap),
            _buildIcon(widget.trailingIcon, metrics.iconSize, foreground)!,
          ],
        ],
      ],
    );

    final buttonBody = AnimatedScale(
      scale: _pressed && !widget.isDisabled && !reducedMotion
          ? AppMotion.buttonPressScale
          : 1,
      duration: AppDurations.instant,
      curve: AppCurves.standard,
      child: AnimatedContainer(
        key: _measureKey,
        duration: AppDurations.instant,
        curve: AppCurves.standard,
        height: isLink ? null : metrics.height,
        constraints: BoxConstraints(
          minWidth: isLink ? 0 : (_lockedMinWidth ?? metrics.minWidth),
          minHeight: isLink ? 0 : metrics.height,
        ),
        padding: isLink
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: _clipBorderRadius(borderRadius),
          border: palette.border == null
              ? null
              : Border.all(color: palette.border!),
        ),
        child: content,
      ),
    );

    final ringColor = widget.error && !widget.isDisabled
        ? colors.statusDangerBorder
        : (_focused ? palette.focusRing : Colors.transparent);

    return Semantics(
      button: true,
      enabled: !widget.isDisabled,
      label: widget.semanticLabel,
      child: Focus(
        focusNode: _effectiveFocusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (widget.isDisabled) return KeyEventResult.ignored;
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onPressed?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: widget.isDisabled
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.isDisabled
                ? null
                : (_) => setState(() => _pressed = true),
            onTapUp: widget.isDisabled
                ? null
                : (_) => setState(() => _pressed = false),
            onTapCancel: widget.isDisabled
                ? null
                : () => setState(() => _pressed = false),
            onTap: widget.isDisabled ? null : widget.onPressed,
            child: Container(
              padding: ringColor == Colors.transparent
                  ? EdgeInsets.zero
                  : const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: ringColor == Colors.transparent
                    ? null
                    : Border.all(color: ringColor, width: 2),
              ),
              child: buttonBody,
            ),
          ),
        ),
      ),
    );
  }

  BorderRadius _clipBorderRadius(BorderRadius radius) {
    if (widget.clipLeadingRadius && widget.clipTrailingRadius) {
      return radius;
    }
    final corners = radius.resolve(Directionality.of(context));
    return BorderRadius.only(
      topLeft: widget.clipLeadingRadius ? corners.topLeft : Radius.zero,
      bottomLeft: widget.clipLeadingRadius ? corners.bottomLeft : Radius.zero,
      topRight: widget.clipTrailingRadius ? corners.topRight : Radius.zero,
      bottomRight: widget.clipTrailingRadius
          ? corners.bottomRight
          : Radius.zero,
    );
  }
}
