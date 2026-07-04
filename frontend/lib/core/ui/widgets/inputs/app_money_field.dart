import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';

/// Currency amount input with affix, grouping on blur, and 2-decimal scale.
class AppMoneyField extends StatefulWidget {
  static final Decimal _defaultMin = Decimal.zero;

  AppMoneyField({
    this.focusNode,
    this.onValueChange,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.hintText,
    this.currency = 'EGP',
    this.value,
    this.defaultValue,
    Decimal? min,
    super.key,
  }) : min = min ?? _defaultMin;

  final FocusNode? focusNode;
  final ValueChanged<Decimal?>? onValueChange;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? hintText;
  final String currency;
  final Decimal? value;
  final Decimal? defaultValue;
  final Decimal min;

  @override
  State<AppMoneyField> createState() => _AppMoneyFieldState();
}

class _AppMoneyFieldState extends State<AppMoneyField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;
  Decimal? _internal;
  Locale? _resolvedLocale;

  @override
  void initState() {
    super.initState();
    _internal = widget.value ?? widget.defaultValue;
    // Locale-aware formatting requires inherited widgets; apply in didChangeDependencies.
    _controller = TextEditingController(text: _rawText(_internal));
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_resolvedLocale == locale) {
      return;
    }
    _resolvedLocale = locale;
    _syncDisplayedText();
  }

  @override
  void didUpdateWidget(covariant AppMoneyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != null && !_focused) {
      _internal = widget.value;
      _syncDisplayedText();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (_focused == focused) return;
    setState(() => _focused = focused);
    if (focused) {
      final current = _numericValue;
      if (current != null) {
        _controller.text = current.toString();
      }
    } else {
      _commitValue(_controller.text);
    }
  }

  Decimal? get _numericValue => widget.value ?? _internal;

  String _intlLocale(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'ar' ? 'ar-EG' : 'en-EG';
  }

  String _formatMoney(BuildContext context, Decimal value) {
    final formatter = NumberFormat('#,##0.00', _intlLocale(context));
    return formatter.format(value.toDouble());
  }

  String _rawText(Decimal? value) => value?.toString() ?? '';

  void _syncDisplayedText() {
    if (_focused) return;
    final value = _numericValue;
    _controller.text = value != null ? _formatMoney(context, value) : '';
  }

  Decimal? _parseMoney(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d.-]'), '');
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return null;
    return Decimal.tryParse(cleaned);
  }

  void _commitValue(String raw) {
    var parsed = _parseMoney(raw);
    if (parsed != null && parsed < widget.min) {
      parsed = widget.min;
    }
    if (widget.value == null) {
      setState(() => _internal = parsed);
    }
    widget.onValueChange?.call(parsed);
    _syncDisplayedText();
  }

  void _handleChanged(String raw) {
    _controller.value = _controller.value.copyWith(
      text: raw,
      selection: TextSelection.collapsed(offset: raw.length),
    );
    final parsed = _parseMoney(raw);
    if (_focused) {
      if (widget.value == null) {
        _internal = parsed;
      }
      widget.onValueChange?.call(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final affix = AppInputAffix(label: widget.currency, size: widget.size);

    return AppInputFrame(
      focusNode: _focusNode,
      size: widget.size,
      invalid: widget.invalid,
      disabled: widget.disabled,
      readOnly: widget.readOnly,
      leading: isRtl ? null : affix,
      trailing: isRtl ? affix : null,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: !widget.disabled,
        readOnly: widget.readOnly,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.end,
        style: appBareInputTextStyle(context, size: widget.size, disabled: widget.disabled, readOnly: widget.readOnly),
        onChanged: _handleChanged,
        decoration: appBareInputDecoration(
          context: context,
          size: widget.size,
          hintText: widget.hintText,
          disabled: widget.disabled,
          readOnly: widget.readOnly,
        ),
        cursorColor: context.colors.borderFocus,
      ),
    );
  }
}
