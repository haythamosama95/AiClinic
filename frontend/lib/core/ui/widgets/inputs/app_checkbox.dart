import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Tristate checkbox supporting checked, unchecked, and indeterminate states.
class AppCheckbox extends StatefulWidget {
  const AppCheckbox({
    this.value,
    this.tristate = false,
    this.onChanged,
    this.disabled = false,
    this.invalid = false,
    this.label,
    this.semanticLabel,
    super.key,
  });

  /// When [tristate] is true, null represents indeterminate.
  final bool? value;
  final bool tristate;
  final ValueChanged<bool?>? onChanged;
  final bool disabled;
  final bool invalid;
  final String? label;
  final String? semanticLabel;

  @override
  State<AppCheckbox> createState() => _AppCheckboxState();
}

class _AppCheckboxState extends State<AppCheckbox> {
  static const double _size = AppSpacing.s5;

  bool get _isInteractive => !widget.disabled && widget.onChanged != null;

  bool? get _effectiveValue => widget.tristate ? widget.value : widget.value;

  bool get _isChecked => _effectiveValue == true;

  bool get _isIndeterminate =>
      widget.tristate && _effectiveValue == null;

  void _toggle() {
    if (!_isInteractive) return;
    if (widget.tristate) {
      final current = widget.value;
      if (current == null) {
        widget.onChanged?.call(true);
      } else if (current) {
        widget.onChanged?.call(false);
      } else {
        widget.onChanged?.call(null);
      }
    } else {
      widget.onChanged?.call(!(widget.value ?? false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final duration = AppMotion.reduced(context)
        ? AppDurations.instant
        : AppDurations.fast;
    final selected = _isChecked || _isIndeterminate;

    final box = Semantics(
      checked: _isIndeterminate ? null : _isChecked,
      mixed: _isIndeterminate,
      enabled: _isInteractive,
      label: widget.semanticLabel ?? widget.label,
      onTap: _isInteractive ? _toggle : null,
      child: AppPressable.builder(
        onTap: _toggle,
        enabled: _isInteractive,
        borderRadius: AppRadii.smAll,
        builder: (context, states, _) {
          final pressed = states.contains(WidgetState.pressed);
          final borderColor = widget.invalid
              ? colors.statusDangerBorder
              : selected
              ? colors.actionPrimary
              : colors.borderDefault;
          final background = selected
              ? colors.actionPrimary
              : colors.surfaceDefault;
          final foreground = selected
              ? colors.actionPrimaryFg
              : colors.iconDefault;

          return AnimatedContainer(
            duration: duration,
            curve: AppEasings.standard,
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              color: widget.disabled
                  ? background.withValues(alpha: 0.5)
                  : background,
              borderRadius: AppRadii.smAll,
              border: Border.all(
                color: widget.disabled
                    ? borderColor.withValues(alpha: 0.5)
                    : borderColor,
              ),
            ),
            child: Center(
              child: AnimatedScale(
                scale: pressed ? 0.85 : 1,
                duration: duration,
                curve: AppEasings.out,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: AppEasings.out,
                  switchOutCurve: AppEasings.inCurve,
                  child: selected
                      ? AppIcon(
                          key: ValueKey(_isIndeterminate),
                          icon: _isIndeterminate
                              ? LucideIcons.minus
                              : LucideIcons.check,
                          dimension: AppSpacing.s3 + AppSpacing.s0_5,
                          color: foreground,
                        )
                      : const SizedBox.shrink(key: ValueKey('empty')),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (widget.label == null) return box;

    return MergeSemantics(
      child: GestureDetector(
        onTap: _isInteractive ? _toggle : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            box,
            const SizedBox(width: AppSpacing.s2),
            Text(
              widget.label!,
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
