import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Application-owned number input with optional steppers (web `NumberInput`).
class AppNumberInput extends StatefulWidget {
  const AppNumberInput({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onValueChange,
    this.initialValue,
    this.placeholder,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.showSteppers = true,
    this.min,
    this.max,
    this.step = 1,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<num?>? onValueChange;
  final num? initialValue;
  final String? placeholder;
  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final bool showSteppers;
  final num? min;
  final num? max;
  final num step;

  @override
  State<AppNumberInput> createState() => _AppNumberInputState();
}

class _AppNumberInputState extends State<AppNumberInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _ownsController = false;
  var _ownsFocusNode = false;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController(text: _formatValue(widget.initialValue));
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep local edits while focused — syncing initialValue on every parent rebuild
    // resets the controller and selects all text, which breaks typed input.
    if (_ownsController && !_focusNode.hasFocus && widget.initialValue != oldWidget.initialValue) {
      final text = _formatValue(widget.initialValue);
      if (_controller.text != text) {
        _controller.text = text;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  String _formatValue(num? value) {
    if (value == null) return '';
    if (value is int || value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toString();
  }

  num? _parseValue(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return num.tryParse(trimmed);
  }

  num _clamp(num value) {
    var next = value;
    if (widget.min != null) next = next < widget.min! ? widget.min! : next;
    if (widget.max != null) next = next > widget.max! ? widget.max! : next;
    return next;
  }

  void _commitValue(num? value, {bool notify = true}) {
    final clamped = value == null ? null : _clamp(value);
    final text = _formatValue(clamped);
    if (_controller.text != text) {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    }
    if (notify) {
      widget.onChanged?.call(text);
      widget.onValueChange?.call(clamped);
    }
  }

  void _step(num delta) {
    final current = _parseValue(_controller.text) ?? widget.initialValue ?? 0;
    _commitValue(current + delta * widget.step);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _step(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = appInputMetrics(widget.size);
    final textStyle = appBareInputTextStyle(context, widget.size, disabled: widget.disabled);
    final steppersDisabled = widget.disabled || widget.readOnly;

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standardCurve,
      height: metrics.height,
      decoration: appInputWrapperDecoration(
        context,
        size: widget.size,
        invalid: widget.invalid,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
        focused: _focused,
      ),
      padding: EdgeInsetsDirectional.only(
        start: widget.showSteppers ? AppSpacing.space1 : metrics.horizontalPadding,
        end: widget.showSteppers ? AppSpacing.space1 : metrics.horizontalPadding,
      ),
      child: Row(
        children: [
          if (widget.showSteppers)
            _StepperButton(
              icon: Icons.remove,
              label: 'Decrease',
              disabled: steppersDisabled,
              onPressed: steppersDisabled ? null : () => _step(-1),
            ),
          Expanded(
            child: Semantics(
              identifier: widget.id,
              textField: true,
              readOnly: widget.readOnly,
              enabled: !widget.disabled,
              child: Focus(
                onKeyEvent: _handleKey,
                child: appWrapMaterialInput(
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !widget.disabled,
                    readOnly: widget.readOnly,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.end,
                    style: textStyle,
                    cursorColor: colors.textPrimary,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'))],
                    onChanged: (value) {
                      widget.onChanged?.call(value);
                      widget.onValueChange?.call(_parseValue(value));
                    },
                    onEditingComplete: () => _commitValue(_parseValue(_controller.text)),
                    decoration: appBareInputDecoration(
                      context,
                      size: widget.size,
                      disabled: widget.disabled,
                      hintText: widget.placeholder,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.showSteppers)
            _StepperButton(
              icon: Icons.add,
              label: 'Increase',
              disabled: steppersDisabled,
              onPressed: steppersDisabled ? null : () => _step(1),
            ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatefulWidget {
  const _StepperButton({required this.icon, required this.label, required this.disabled, this.onPressed});

  final IconData icon;
  final String label;
  final bool disabled;
  final VoidCallback? onPressed;

  @override
  State<_StepperButton> createState() => _StepperButtonState();
}

class _StepperButtonState extends State<_StepperButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      enabled: !widget.disabled,
      label: widget.label,
      child: MouseRegion(
        onEnter: widget.disabled ? null : (_) => setState(() => _hovered = true),
        onExit: widget.disabled ? null : (_) => setState(() => _hovered = false),
        cursor: widget.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: AppPressable(
          enabled: !widget.disabled,
          onPressed: widget.onPressed,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered && !widget.disabled ? colors.surfaceHover : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(widget.icon, size: 16, color: widget.disabled ? colors.textDisabled : colors.iconDefault),
          ),
        ),
      ),
    );
  }
}
