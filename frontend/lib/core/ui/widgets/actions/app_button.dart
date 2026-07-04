import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

import '_button_shared.dart';
import 'app_spinner.dart';

export '_button_shared.dart' show AppButtonSize, AppButtonVariant;

/// Labeled action control with optional leading and trailing icons.
class AppButton extends StatefulWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.disabled = false,
    this.error = false,
    this.fullWidth = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool loading;
  final bool disabled;
  final bool error;
  final bool fullWidth;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  final GlobalKey _measureKey = GlobalKey();
  double? _lockedWidth;

  bool get _isDisabled => widget.disabled || widget.loading;

  @override
  void didUpdateWidget(covariant AppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading && !oldWidget.loading) {
      _captureWidth();
    }
    if (!widget.loading && oldWidget.loading) {
      _lockedWidth = null;
    }
  }

  void _captureWidth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _measureKey.currentContext;
      if (context == null) return;
      final width = context.size?.width;
      if (width != null && mounted) {
        setState(() => _lockedWidth = width);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final height = AppButtonShared.height(widget.size);
    final borderRadius = AppRadii.mdAll;
    final spinnerSize =
        widget.size == AppButtonSize.lg ? AppSpinnerSize.md : AppSpinnerSize.sm;
    final iconDimension = AppButtonShared.iconDimension(widget.size);
    final gap = AppButtonShared.gap(widget.size);
    final textStyle = AppButtonShared.textStyle(context, widget.size);
    final showUnderline =
        widget.variant == AppButtonVariant.link &&
        !_isDisabled;

    Widget content = AppPressable.builder(
      enabled: !_isDisabled,
      onTap: widget.onPressed,
      focusRingVariant: AppButtonShared.focusRingVariant(widget.variant),
      borderRadius: borderRadius,
      builder: (context, states, _) {
        final background = AppButtonShared.background(
          colors,
          widget.variant,
          states,
          disabled: _isDisabled,
        );
        final resolvedForeground = AppButtonShared.foreground(
          colors,
          widget.variant,
          states,
          disabled: _isDisabled,
        );
        final borderColor = AppButtonShared.borderColor(
          colors,
          widget.variant,
          disabled: _isDisabled,
        );
        final underline = showUnderline && states.contains(WidgetState.hovered);

        return AnimatedContainer(
          duration: AppDurations.instant,
          curve: AppEasings.standard,
          height: height,
          constraints: BoxConstraints(
            minWidth: widget.variant == AppButtonVariant.link
                ? 0
                : AppButtonShared.minWidth(widget.size),
          ),
          padding: AppButtonShared.padding(widget.size, widget.variant),
          decoration: AppButtonShared.decoration(
            background: background,
            borderRadius: borderRadius,
            borderColor: borderColor,
            error: widget.error && !_isDisabled,
            colors: colors,
          ),
          child: Row(
            mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                AppSpinner(
                  size: spinnerSize,
                  color: resolvedForeground,
                )
              else if (widget.leadingIcon != null)
                AppIcon(
                  icon: widget.leadingIcon!,
                  dimension: iconDimension,
                  color: resolvedForeground,
                ),
              if (widget.loading || widget.leadingIcon != null)
                SizedBox(width: gap),
              Flexible(
                child: Text(
                  widget.label,
                  style: textStyle.copyWith(
                    color: resolvedForeground,
                    decoration: underline ? TextDecoration.underline : null,
                    decorationColor: resolvedForeground,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              if (!widget.loading && widget.trailingIcon != null) ...[
                SizedBox(width: gap),
                AppIcon(
                  icon: widget.trailingIcon!,
                  dimension: iconDimension,
                  color: resolvedForeground,
                ),
              ],
            ],
          ),
        );
      },
    );

    content = Semantics(
      button: true,
      enabled: !_isDisabled,
      label: widget.label,
      onTap: _isDisabled ? null : widget.onPressed,
      child: content,
    );

    if (widget.loading) {
      content = Semantics(
        liveRegion: true,
        child: ExcludeSemantics(child: content),
      );
    }

    if (widget.fullWidth) {
      content = SizedBox(width: double.infinity, child: content);
    } else if (widget.loading && _lockedWidth != null) {
      content = SizedBox(width: _lockedWidth, child: content);
    }

    return KeyedSubtree(key: _measureKey, child: content);
  }
}
