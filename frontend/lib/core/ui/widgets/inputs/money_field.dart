import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';

/// Currency-prefixed money field with tabular figures and locale formatting.
class AppMoneyField extends StatefulWidget {
  const AppMoneyField({
    super.key,
    this.controller,
    this.focusNode,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.currency = 'EGP',
    this.value,
    this.min = 0,
    this.hintText,
    this.locale,
    this.onValueChange,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String currency;
  final double? value;
  final double min;
  final String? hintText;
  final String? locale;
  final ValueChanged<double?>? onValueChange;

  @override
  State<AppMoneyField> createState() => _AppMoneyFieldState();
}

class _AppMoneyFieldState extends State<AppMoneyField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focused = false;

  String get _intlLocale {
    final code = widget.locale ?? Localizations.localeOf(context).languageCode;
    return code == 'ar' ? 'ar-EG' : 'en-EG';
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode.addListener(_handleFocus);
    if (widget.value != null) {
      _controller.text = _format(widget.value!);
    }
  }

  @override
  void didUpdateWidget(AppMoneyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focused && widget.value != null) {
      _controller.text = _format(widget.value!);
    }
  }

  void _handleFocus() {
    if (_focused != _focusNode.hasFocus) {
      setState(() {
        _focused = _focusNode.hasFocus;
        if (_focused && widget.value != null) {
          _controller.text = widget.value!.toString();
        } else if (!_focused) {
          final parsed = _parse(_controller.text);
          _controller.text = parsed != null ? _format(parsed) : '';
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocus);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  String _format(double value) {
    return NumberFormat('#,##0.00', _intlLocale).format(value);
  }

  double? _parse(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d.-]'), '');
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return null;
    final n = double.tryParse(cleaned);
    return n;
  }

  void _commit(String raw) {
    var parsed = _parse(raw);
    if (parsed != null && parsed < widget.min) parsed = widget.min;
    widget.onValueChange?.call(parsed);
    _controller.text = parsed != null ? _format(parsed) : '';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Focus(
        onFocusChange: (f) {
          if (!f) _commit(_controller.text);
          _handleFocus();
        },
        child: Container(
          constraints: BoxConstraints(
            minHeight: AppInputStyles.height(widget.size),
          ),
          padding: AppInputStyles.padding(widget.size),
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
              Text(
                widget.currency,
                style: AppInputStyles.affixTextStyle(
                  context,
                  widget.size,
                ).copyWith(color: colors.textTertiary),
              ),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: !widget.disabled,
                  readOnly: widget.readOnly,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
                    contentPadding: EdgeInsets.zero,
                    hintText: widget.hintText,
                    hintStyle: AppInputStyles.textStyle(
                      context,
                      widget.size,
                    ).copyWith(color: colors.textPlaceholder),
                  ),
                  onChanged: (value) {
                    if (_focused) widget.onValueChange?.call(_parse(value));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
