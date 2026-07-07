import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Application-owned switch (web `Switch`).
class AppSwitch extends StatefulWidget {
  const AppSwitch({
    super.key,
    this.value,
    this.initialValue = false,
    this.onChanged,
    this.disabled = false,
    this.invalid = false,
    this.label,
  });

  /// Controlled state. Omit for uncontrolled mode.
  final bool? value;
  final bool initialValue;
  final ValueChanged<bool>? onChanged;
  final bool disabled;
  final bool invalid;
  final String? label;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch> {
  static const _trackWidth = 44.0;
  static const _trackHeight = 24.0;
  static const _thumbSize = 20.0;
  static const _thumbInset = 2.0;

  late bool _internalValue;
  final _focusNode = FocusNode();
  var _focused = false;

  bool get _isControlled => widget.value != null;

  bool get _effectiveValue => widget.value ?? _internalValue;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.initialValue;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isControlled && widget.initialValue != oldWidget.initialValue) {
      _internalValue = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _handlePressed() {
    if (widget.disabled) return;
    if (_isControlled && widget.onChanged == null) return;

    final next = !_effectiveValue;
    if (!_isControlled) {
      setState(() => _internalValue = next);
    }
    widget.onChanged?.call(next);
  }

  Widget _buildControl() {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final focusRing = widget.invalid
        ? appInputInvalidFocusRingColor(colors)
        : appInputFocusRingColor(context);

    return Semantics(
      toggled: _effectiveValue,
      enabled: !widget.disabled,
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: !widget.disabled,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent || widget.disabled) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.space || event.logicalKey == LogicalKeyboardKey.enter) {
            _handlePressed();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AppPressable(
          enabled: !widget.disabled,
          onPressed: !widget.disabled && (!_isControlled || widget.onChanged != null)
              ? _handlePressed
              : null,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.standardCurve,
            width: _trackWidth,
            height: _trackHeight,
            decoration: BoxDecoration(
              color: _effectiveValue ? colors.actionPrimary : colors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(
                color: widget.invalid
                    ? colors.statusDangerBorder
                    : (_effectiveValue ? colors.actionPrimary : colors.borderDefault),
              ),
              boxShadow: _focused ? [BoxShadow(color: focusRing, blurRadius: 0, spreadRadius: 2)] : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedPositionedDirectional(
                  duration: AppMotion.fast,
                  curve: AppMotion.standardCurve,
                  start: _effectiveValue ? null : _thumbInset,
                  end: _effectiveValue ? _thumbInset : null,
                  top: _thumbInset,
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: colors.surfaceDefault,
                      shape: BoxShape.circle,
                      boxShadow: elevation.shadows1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final control = _buildControl();

    if (widget.label == null) {
      return Opacity(opacity: widget.disabled ? 0.5 : 1, child: control);
    }

    return Opacity(
      opacity: widget.disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: widget.disabled ? null : _handlePressed,
        behavior: HitTestBehavior.translucent,
        child: MouseRegion(
          cursor: widget.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              control,
              const SizedBox(width: AppSpacing.space3),
              Text(widget.label!, style: AppTypography.body(context).copyWith(color: colors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}
