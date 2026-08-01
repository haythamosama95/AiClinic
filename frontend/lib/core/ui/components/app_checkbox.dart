import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Tri-state value for [AppCheckbox] (web `checked: boolean | 'indeterminate'`).
enum AppCheckboxState { unchecked, checked, indeterminate }

/// Application-owned checkbox (web `Checkbox`).
class AppCheckbox extends StatefulWidget {
  const AppCheckbox({
    super.key,
    this.value,
    this.initialValue = AppCheckboxState.unchecked,
    this.onChanged,
    this.disabled = false,
    this.invalid = false,
    this.label,
  });

  /// Controlled state. Omit for uncontrolled mode.
  final AppCheckboxState? value;
  final AppCheckboxState initialValue;
  final ValueChanged<AppCheckboxState>? onChanged;
  final bool disabled;
  final bool invalid;
  final String? label;

  @override
  State<AppCheckbox> createState() => _AppCheckboxState();
}

class _AppCheckboxState extends State<AppCheckbox> {
  static const _boxSize = 20.0;
  static const _iconSize = 14.0;

  late AppCheckboxState _internalValue;
  final _focusNode = FocusNode();
  var _focused = false;

  bool get _isControlled => widget.value != null;

  AppCheckboxState get _effectiveValue => widget.value ?? _internalValue;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.initialValue;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppCheckbox oldWidget) {
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

  AppCheckboxState _nextValue(AppCheckboxState current) {
    return switch (current) {
      AppCheckboxState.unchecked => AppCheckboxState.checked,
      AppCheckboxState.checked => AppCheckboxState.unchecked,
      AppCheckboxState.indeterminate => AppCheckboxState.checked,
    };
  }

  void _handlePressed() {
    if (widget.disabled) return;
    if (_isControlled && widget.onChanged == null) return;

    final next = _nextValue(_effectiveValue);
    if (!_isControlled) {
      setState(() => _internalValue = next);
    }
    widget.onChanged?.call(next);
  }

  BoxDecoration _boxDecoration(AppSemanticColors colors, Brightness brightness) {
    final checked = _effectiveValue != AppCheckboxState.unchecked;
    final focusRing = widget.invalid
        ? appInputInvalidFocusRingColor(colors)
        : appInputFocusRingColor(context);

    return BoxDecoration(
      color: checked ? colors.actionPrimary : colors.surfaceDefault,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(
        color: widget.invalid
            ? colors.statusDangerBorder
            : (checked ? colors.actionPrimary : colors.borderDefault),
      ),
      boxShadow: _focused ? [BoxShadow(color: focusRing, blurRadius: 0, spreadRadius: 2)] : null,
    );
  }

  Widget _buildIndicator(AppSemanticColors colors) {
    if (_effectiveValue == AppCheckboxState.unchecked) {
      return const SizedBox.shrink();
    }

    final icon = _effectiveValue == AppCheckboxState.indeterminate ? Icons.remove : Icons.check;
    return Icon(icon, size: _iconSize, color: colors.actionPrimaryFg);
  }

  Widget _buildControl() {
    final colors = context.appColors;
    final brightness = Theme.of(context).brightness;

    return Semantics(
      checked: _effectiveValue == AppCheckboxState.checked
          ? true
          : (_effectiveValue == AppCheckboxState.indeterminate ? null : false),
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
          onPressed: !widget.disabled &&
                  (!_isControlled || widget.onChanged != null)
              ? _handlePressed
              : null,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.standardCurve,
            width: _boxSize,
            height: _boxSize,
            decoration: _boxDecoration(colors, brightness),
            child: Center(child: _buildIndicator(colors)),
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
              const SizedBox(width: AppSpacing.space2),
              Text(widget.label!, style: AppTypography.body(context).copyWith(color: colors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}
