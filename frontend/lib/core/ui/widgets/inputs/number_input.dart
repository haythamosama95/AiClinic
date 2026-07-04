import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';

/// Numeric input with optional +/- stepper controls.
class AppNumberInput extends StatefulWidget {
  const AppNumberInput({
    super.key,
    this.controller,
    this.focusNode,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.showSteppers = true,
    this.min,
    this.max,
    this.step = 1,
    this.hintText,
    this.onChanged,
    this.onValueChange,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final bool showSteppers;
  final num? min;
  final num? max;
  final num step;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<num?>? onValueChange;

  @override
  State<AppNumberInput> createState() => _AppNumberInputState();
}

class _AppNumberInputState extends State<AppNumberInput> {
  late TextEditingController _controller;
  bool _ownsController = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  num? _parseValue() {
    final parsed = num.tryParse(_controller.text);
    return parsed;
  }

  num _clamp(num value) {
    var v = value;
    if (widget.min != null) v = v < widget.min! ? widget.min! : v;
    if (widget.max != null) v = v > widget.max! ? widget.max! : v;
    return v;
  }

  void _applyValue(num value) {
    final clamped = _clamp(value);
    final text = clamped.toString();
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    widget.onChanged?.call(text);
    widget.onValueChange?.call(clamped);
    setState(() {});
  }

  void _step(num delta) {
    final current = _parseValue() ?? 0;
    _applyValue(current + delta * widget.step);
  }

  Widget _stepperButton({required num delta, required String label}) {
    final colors = context.colors;
    return IconButton(
      icon: Icon(
        delta > 0 ? Icons.add : Icons.remove,
        size: 18,
        color: colors.iconDefault,
      ),
      onPressed: widget.disabled || widget.readOnly ? null : () => _step(delta),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      tooltip: label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _step(1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _step(-1);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        constraints: BoxConstraints(
          minHeight: AppInputStyles.height(widget.size),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: widget.showSteppers ? AppSpacing.s1 : AppSpacing.s3,
        ),
        decoration: AppInputStyles.wrapperDecoration(
          context,
          size: widget.size,
          invalid: widget.invalid,
          disabled: widget.disabled,
          readOnly: widget.readOnly,
          focused: _focused,
        ),
        child: Row(
          children: [
            if (widget.showSteppers)
              _stepperButton(delta: -1, label: 'Decrease'),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: widget.focusNode,
                enabled: !widget.disabled,
                readOnly: widget.readOnly,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                ],
                textAlign: TextAlign.end,
                style: AppInputStyles.affixTextStyle(context, widget.size)
                    .copyWith(
                      color: widget.disabled
                          ? colors.textDisabled
                          : colors.textPrimary,
                    ),
                cursorColor: colors.borderFocus,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                  ),
                  hintText: widget.hintText,
                  hintStyle: AppInputStyles.textStyle(
                    context,
                    widget.size,
                  ).copyWith(color: colors.textPlaceholder),
                ),
                onChanged: (value) {
                  widget.onChanged?.call(value);
                  widget.onValueChange?.call(num.tryParse(value));
                  setState(() {});
                },
              ),
            ),
            if (widget.showSteppers)
              _stepperButton(delta: 1, label: 'Increase'),
          ],
        ),
      ),
    );
  }
}
