import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';

/// Numeric input with optional stepper buttons and keyboard arrow support.
class AppNumberField extends StatefulWidget {
  const AppNumberField({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onValueChange,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.hintText,
    this.showSteppers = true,
    this.min,
    this.max,
    this.step = 1,
    this.value,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<num?>? onValueChange;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? hintText;
  final bool showSteppers;
  final num? min;
  final num? max;
  final num step;
  final num? value;

  @override
  State<AppNumberField> createState() => _AppNumberFieldState();
}

class _AppNumberFieldState extends State<AppNumberField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController(
        text: widget.value?.toString() ?? '',
      );
      _ownsController = true;
    }
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
  }

  @override
  void didUpdateWidget(covariant AppNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != null) {
      final text = widget.value.toString();
      if (_controller.text != text) {
        _controller.text = text;
      }
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  num? get _currentValue {
    final parsed = num.tryParse(_controller.text);
    return parsed;
  }

  num _clamp(num value) {
    var result = value;
    if (widget.min != null) {
      result = result < widget.min! ? widget.min! : result;
    }
    if (widget.max != null) {
      result = result > widget.max! ? widget.max! : result;
    }
    return result;
  }

  void _applyValue(num next) {
    final clamped = _clamp(next);
    final text = clamped.toString();
    _controller.text = text;
    widget.onChanged?.call(text);
    widget.onValueChange?.call(clamped);
    setState(() {});
  }

  void _step(num delta) {
    if (widget.disabled || widget.readOnly) return;
    final current = _currentValue ?? 0;
    _applyValue(current + delta * widget.step);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
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
    final canStep = !widget.disabled && !widget.readOnly;

    Widget? leading;
    Widget? trailing;
    if (widget.showSteppers) {
      leading = AppInputStepperButton(
        icon: LucideIcons.minus,
        semanticLabel: 'Decrease',
        onPressed: canStep ? () => _step(-1) : null,
      );
      trailing = AppInputStepperButton(
        icon: LucideIcons.plus,
        semanticLabel: 'Increase',
        onPressed: canStep ? () => _step(1) : null,
      );
    }

    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: AppInputFrame(
        focusNode: _focusNode,
        size: widget.size,
        invalid: widget.invalid,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
        gap: AppSpacing.s1,
        leading: leading,
        trailing: trailing,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: !widget.disabled,
          readOnly: widget.readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
          ],
          textAlign: TextAlign.end,
          style: appBareInputTextStyle(
            context,
            size: widget.size,
            disabled: widget.disabled,
            readOnly: widget.readOnly,
          ),
          onChanged: (value) {
            widget.onChanged?.call(value);
            widget.onValueChange?.call(num.tryParse(value));
          },
          decoration: appBareInputDecoration(
            context: context,
            size: widget.size,
            hintText: widget.hintText,
            disabled: widget.disabled,
            readOnly: widget.readOnly,
          ),
          cursorColor: context.colors.borderFocus,
        ),
      ),
    );
  }
}
