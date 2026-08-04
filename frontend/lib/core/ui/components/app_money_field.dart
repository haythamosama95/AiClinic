import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// Currency input with EGP affix and grouping on blur (web `MoneyField`).
class AppMoneyField extends StatefulWidget {
  const AppMoneyField({
    this.initialValue,
    this.onChanged,
    this.onValueChange,
    this.placeholder,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.currency = 'EGP',
    this.min = 0,
    this.locale = 'en-EG',
    this.id,
    super.key,
  });

  final double? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<double?>? onValueChange;
  final String? placeholder;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String currency;
  final double min;
  final String locale;
  final String? id;

  @override
  State<AppMoneyField> createState() => _AppMoneyFieldState();
}

class _AppMoneyFieldState extends State<AppMoneyField> {
  late final TextEditingController _displayController;
  final _focusNode = FocusNode();
  double? _numericValue;
  var _focused = false;

  NumberFormat get _formatter => NumberFormat('#,##0.00', widget.locale);

  @override
  void initState() {
    super.initState();
    _numericValue = widget.initialValue;
    _displayController = TextEditingController();
    _displayController.text = _formatDisplay(_numericValue);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppMoneyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue && !_focused) {
      _numericValue = widget.initialValue;
      _displayController.text = _formatDisplay(_numericValue);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _displayController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    final focused = _focusNode.hasFocus;
    if (focused && !_focused) {
      setState(() {
        _focused = true;
        if (_numericValue != null) {
          _displayController.text = _numericValue!.toString();
        }
      });
    } else if (!focused && _focused) {
      _commitValue();
    }
  }

  String _formatDisplay(double? value) {
    if (value == null) return '';
    return _formatter.format(value);
  }

  double? _parseMoney(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d.-]'), '');
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return null;
    final parsed = double.tryParse(cleaned);
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  void _commitValue() {
    var next = _parseMoney(_displayController.text);
    if (next != null && next < widget.min) {
      next = widget.min;
    }
    setState(() {
      _focused = false;
      _numericValue = next;
      _displayController.text = _formatDisplay(next);
    });
    widget.onValueChange?.call(next);
  }

  void _handleChanged(String raw) {
    widget.onChanged?.call(raw);
    if (_focused) {
      widget.onValueChange?.call(_parseMoney(raw));
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _displayController,
      focusNode: _focusNode,
      enabled: !widget.disabled,
      readOnly: widget.readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]'))],
      textAlign: TextAlign.end,
      style: widget.disabled
          ? appInputDisabledTextStyle(context, widget.size)
          : appInputTextStyle(context, widget.size),
      cursorColor: context.appColors.textPrimary,
      decoration: appBareInputDecoration(
        context,
        size: widget.size,
        disabled: widget.disabled,
        hintText: widget.placeholder,
      ),
      onChanged: _handleChanged,
    );

    return Semantics(
      identifier: widget.id,
      textField: true,
      child: AppAffixInputWrapper(
        size: widget.size,
        invalid: widget.invalid,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
        focusNode: _focusNode,
        forceLtr: true,
        prefix: widget.currency,
        child: field,
      ),
    );
  }
}
