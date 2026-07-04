import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Boolean toggle with sliding knob and required label support.
class AppSwitch extends StatefulWidget {
  const AppSwitch({
    required this.label,
    this.value = false,
    this.onChanged,
    this.disabled = false,
    this.invalid = false,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool disabled;
  final bool invalid;
  final String? semanticLabel;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch> {
  static const double _trackWidth = AppSpacing.s10 + AppSpacing.s1;
  static const double _trackHeight = AppSpacing.s6;
  static const double _thumbSize = AppSpacing.s5;
  static const double _thumbPadding = AppSpacing.s0_5;

  bool get _isInteractive => !widget.disabled && widget.onChanged != null;

  void _toggle() {
    if (!_isInteractive) return;
    widget.onChanged?.call(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final duration = AppMotion.reduced(context)
        ? AppDurations.instant
        : AppDurations.fast;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final checked = widget.value;

    final track = Semantics(
      toggled: checked,
      enabled: _isInteractive,
      label: widget.semanticLabel ?? widget.label,
      onTap: _isInteractive ? _toggle : null,
      child: AppPressable.builder(
        onTap: _toggle,
        enabled: _isInteractive,
        borderRadius: AppRadii.fullAll,
        builder: (context, states, _) {
          final borderColor = widget.invalid
              ? colors.statusDangerBorder
              : checked
              ? colors.actionPrimary
              : colors.borderDefault;
          final trackColor = checked
              ? colors.actionPrimary
              : colors.surfaceMuted;

          return AnimatedContainer(
            duration: duration,
            curve: AppEasings.standard,
            width: _trackWidth,
            height: _trackHeight,
            padding: const EdgeInsets.all(_thumbPadding),
            decoration: BoxDecoration(
              color: widget.disabled
                  ? trackColor.withValues(alpha: 0.5)
                  : trackColor,
              borderRadius: AppRadii.fullAll,
              border: Border.all(
                color: widget.disabled
                    ? borderColor.withValues(alpha: 0.5)
                    : borderColor,
              ),
            ),
            child: AnimatedAlign(
              duration: duration,
              curve: AppEasings.out,
              alignment: isRtl
                  ? (checked
                      ? AlignmentDirectional.centerStart
                      : AlignmentDirectional.centerEnd)
                  : (checked
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart),
              child: Container(
                width: _thumbSize,
                height: _thumbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceDefault,
                  boxShadow: AppShadows.forContext(context, 1),
                ),
              ),
            ),
          );
        },
      ),
    );

    return Opacity(
      opacity: widget.disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: _isInteractive ? _toggle : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            track,
            const SizedBox(width: AppSpacing.s3),
            Text(
              widget.label,
              style: typography.body.copyWith(
                color: widget.disabled
                    ? colors.textDisabled
                    : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
