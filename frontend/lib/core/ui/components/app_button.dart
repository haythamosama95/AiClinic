import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Application-owned button (`04-components` A1).
class AppButton extends StatefulWidget {
  const AppButton({
    required this.child,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.loading = false,
    this.error = false,
    this.disabled = false,
    this.leadingIcon,
    this.trailingIcon,
    this.borderRadius,
    this.omitTrailingBorder = false,
    this.backgroundGradient,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool error;
  final bool disabled;
  final Widget? leadingIcon;
  final Widget? trailingIcon;

  /// When null, uses the default `AppRadius.md` corners.
  final BorderRadiusGeometry? borderRadius;

  /// Hides the trailing (end) border — used when the button is the start segment of a split button.
  final bool omitTrailingBorder;

  /// When set, renders a gradient fill instead of the variant's solid background.
  final Gradient? backgroundGradient;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  var _hovered = false;
  var _pressed = false;
  double? _lockedWidth;

  bool get _isDisabled => widget.disabled || widget.loading;

  @override
  void didUpdateWidget(covariant AppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading && !oldWidget.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureWidth());
    } else if (!widget.loading) {
      _lockedWidth = null;
    }
  }

  void _captureWidth() {
    final width = context.size?.width;
    if (width != null && mounted) {
      setState(() => _lockedWidth = width);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = _metricsFor(widget.size, widget.variant);
    final usesGradient = widget.backgroundGradient != null && !_isDisabled;
    final palette = _paletteFor(
      colors,
      widget.variant,
      hovered: _hovered,
      pressed: _pressed,
      disabled: _isDisabled,
      usesGradient: usesGradient,
    );
    final borderRadius =
        widget.borderRadius ?? (widget.variant == AppButtonVariant.link ? null : BorderRadius.circular(AppRadius.md));
    final border = usesGradient ? null : _resolveBorder(palette.border, widget.omitTrailingBorder);
    final gradientOverlay = usesGradient ? _gradientOverlayColor(hovered: _hovered, pressed: _pressed) : null;

    final labelStyle = switch (widget.size) {
      AppButtonSize.sm => AppTypography.bodySm(
        context,
      ).copyWith(fontWeight: FontWeight.w500, color: palette.foreground),
      AppButtonSize.md || AppButtonSize.lg => AppTypography.bodyStrong(context).copyWith(color: palette.foreground),
    };

    final rowChildren = <Widget>[];
    if (widget.loading) {
      rowChildren.add(_ButtonSpinner(size: widget.size == AppButtonSize.lg ? 20 : 16, color: palette.foreground));
    } else if (widget.leadingIcon != null) {
      rowChildren.add(
        IconTheme(
          data: IconThemeData(size: metrics.iconSize, color: palette.foreground),
          child: widget.leadingIcon!,
        ),
      );
    }

    if (rowChildren.isNotEmpty) {
      rowChildren.add(SizedBox(width: metrics.gap));
    }

    rowChildren.add(
      Flexible(
        child: DefaultTextStyle(style: labelStyle, child: widget.child),
      ),
    );

    if (!widget.loading && widget.trailingIcon != null) {
      rowChildren
        ..add(SizedBox(width: metrics.gap))
        ..add(
          IconTheme(
            data: IconThemeData(size: metrics.iconSize, color: palette.foreground),
            child: widget.trailingIcon!,
          ),
        );
    }

    // Size lives outside AnimatedContainer so loading width lock does not
    // interpolate between finite and unbounded constraints.
    final buttonBody = ConstrainedBox(
      constraints: BoxConstraints(minWidth: metrics.minWidth),
      child: SizedBox(
        width: widget.loading ? _lockedWidth : null,
        height: metrics.height,
        child: Container(
          height: metrics.height,
          padding: metrics.padding,
          decoration: BoxDecoration(
            gradient: usesGradient ? widget.backgroundGradient : null,
            color: usesGradient ? null : palette.background,
            borderRadius: borderRadius,
            border: border,
          ),
          foregroundDecoration: widget.variant == AppButtonVariant.link && _hovered && !_isDisabled
              ? BoxDecoration(
                  border: Border(bottom: BorderSide(color: palette.foreground, width: 1)),
                )
              : gradientOverlay == null
              ? null
              : BoxDecoration(color: gradientOverlay, borderRadius: borderRadius),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: rowChildren,
          ),
        ),
      ),
    );

    final interactive = MouseRegion(
      onEnter: _isDisabled ? null : (_) => setState(() => _hovered = true),
      onExit: _isDisabled ? null : (_) => setState(() => _hovered = false),
      cursor: _isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: AppPressable(
        enabled: !_isDisabled,
        onPressed: widget.onPressed,
        onPressedChanged: _isDisabled ? null : (pressed) => setState(() => _pressed = pressed),
        child: buttonBody,
      ),
    );

    Widget result = interactive;

    if (widget.error && !_isDisabled) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md + 2),
          border: Border.all(color: colors.statusDangerBorder, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.surfaceDefault, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: interactive,
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      enabled: !_isDisabled,
      onTap: _isDisabled ? null : widget.onPressed,
      label: _semanticLabel(context),
      value: widget.loading ? 'Loading' : null,
      hint: widget.error ? 'Invalid' : null,
      child: FocusableActionDetector(enabled: !_isDisabled, child: result),
    );
  }

  String? _semanticLabel(BuildContext context) {
    if (widget.child case Text text) {
      return text.data ?? text.textSpan?.toPlainText();
    }
    return null;
  }

  Border? _resolveBorder(Border? border, bool omitTrailingBorder) {
    if (border == null || !omitTrailingBorder) return border;
    return Border(top: border.top, bottom: border.bottom, left: border.left);
  }

  Color? _gradientOverlayColor({required bool hovered, required bool pressed}) {
    if (pressed) {
      return Colors.black.withValues(alpha: 0.12);
    }
    if (hovered) {
      return Colors.white.withValues(alpha: 0.1);
    }
    return null;
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(color)),
      ),
    );
  }
}

enum AppButtonVariant { primary, secondary, ghost, danger, ai, link }

enum AppButtonSize { sm, md, lg }

class _ButtonMetrics {
  const _ButtonMetrics({
    required this.height,
    required this.minWidth,
    required this.padding,
    required this.gap,
    required this.iconSize,
  });

  final double height;
  final double minWidth;
  final EdgeInsets padding;
  final double gap;
  final double iconSize;
}

_ButtonMetrics _metricsFor(AppButtonSize size, AppButtonVariant variant) {
  if (variant == AppButtonVariant.link) {
    return const _ButtonMetrics(
      height: 36,
      minWidth: 0,
      padding: EdgeInsets.zero,
      gap: AppSpacing.space2,
      iconSize: 16,
    );
  }

  return switch (size) {
    AppButtonSize.sm => const _ButtonMetrics(
      height: 28,
      minWidth: 72,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.space2),
      gap: 6,
      iconSize: 16,
    ),
    AppButtonSize.md => const _ButtonMetrics(
      height: 36,
      minWidth: 88,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.space3),
      gap: AppSpacing.space2,
      iconSize: 16,
    ),
    AppButtonSize.lg => const _ButtonMetrics(
      height: 44,
      minWidth: 104,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.space4),
      gap: AppSpacing.space2,
      iconSize: 20,
    ),
  };
}

class _ButtonPalette {
  const _ButtonPalette({required this.background, required this.foreground, this.border});

  final Color background;
  final Color foreground;
  final Border? border;
}

_ButtonPalette _paletteFor(
  AppSemanticColors colors,
  AppButtonVariant variant, {
  required bool hovered,
  required bool pressed,
  required bool disabled,
  bool usesGradient = false,
}) {
  if (disabled) {
    if (variant == AppButtonVariant.link) {
      return _ButtonPalette(background: Colors.transparent, foreground: colors.textDisabled);
    }
    return _ButtonPalette(
      background: colors.actionDisabledBg,
      foreground: colors.textDisabled,
      border: variant == AppButtonVariant.secondary ? Border.all(color: Colors.transparent) : null,
    );
  }

  Color bg(Color base, Color hover, Color active) {
    if (pressed) return active;
    if (hovered) return hover;
    return base;
  }

  if (usesGradient) {
    return _ButtonPalette(background: Colors.transparent, foreground: colors.actionPrimaryFg);
  }

  return switch (variant) {
    AppButtonVariant.primary => _ButtonPalette(
      background: bg(colors.actionPrimary, colors.actionPrimaryHover, colors.actionPrimaryActive),
      foreground: colors.actionPrimaryFg,
    ),
    AppButtonVariant.secondary => _ButtonPalette(
      background: bg(colors.actionSecondary, colors.surfaceHover, colors.surfaceMuted),
      foreground: colors.actionSecondaryFg,
      border: Border.all(color: colors.borderDefault),
    ),
    AppButtonVariant.ghost => _ButtonPalette(
      background: bg(Colors.transparent, colors.actionSubtleHover, colors.surfaceMuted),
      foreground: colors.textPrimary,
    ),
    AppButtonVariant.danger => _ButtonPalette(
      background: bg(colors.actionDanger, colors.actionDangerHover, colors.actionDangerActive),
      foreground: colors.actionDangerFg,
    ),
    AppButtonVariant.ai => _ButtonPalette(
      background: bg(colors.actionAi, colors.actionAiHover, colors.actionAi),
      foreground: colors.actionAiFg,
    ),
    AppButtonVariant.link => _ButtonPalette(
      background: Colors.transparent,
      foreground: pressed ? colors.textPrimary : (hovered ? colors.textPrimary : colors.textLink),
    ),
  };
}
