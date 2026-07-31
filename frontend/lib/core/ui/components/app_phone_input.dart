import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

const _defaultCountryCode = '+20';

String formatPhoneDigits(String input) {
  final d = input.replaceAll(RegExp(r'\D'), '');
  final limited = d.length <= 10 ? d : d.substring(0, 10);
  if (limited.length <= 3) return limited;
  if (limited.length <= 6) return '${limited.substring(0, 3)} ${limited.substring(3)}';
  return '${limited.substring(0, 3)} ${limited.substring(3, 6)} ${limited.substring(6)}';
}

/// Phone input with fixed country code and 3-3-4 grouping (web `PhoneInput`).
class AppPhoneInput extends StatefulWidget {
  const AppPhoneInput({
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onValueChange,
    this.placeholder = '10x xxx xxxx',
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.countryCode = _defaultCountryCode,
    this.id,
    super.key,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onValueChange;
  final String? placeholder;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String countryCode;
  final String? id;

  @override
  State<AppPhoneInput> createState() => _AppPhoneInputState();
}

class _AppPhoneInputState extends State<AppPhoneInput> {
  TextEditingController? _internalController;
  final _focusNode = FocusNode();
  String _digits = '';

  TextEditingController get _controller => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue ?? '';
    _digits = initial.replaceAll(RegExp(r'\D'), '');
    if (_digits.length > 10) _digits = _digits.substring(0, 10);
    if (widget.controller == null) {
      _internalController = TextEditingController(text: formatPhoneDigits(_digits));
    } else {
      widget.controller!.text = formatPhoneDigits(_digits);
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleChanged(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length <= 10 ? digits : digits.substring(0, 10);
    final formatted = formatPhoneDigits(limited);
    _digits = limited;
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    widget.onValueChange?.call(limited);
    widget.onChanged?.call(limited);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: !widget.disabled,
      readOnly: widget.readOnly,
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      style: widget.disabled
          ? appInputDisabledTextStyle(context, widget.size)
          : appInputTextStyle(context, widget.size),
      cursorColor: colors.textPrimary,
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
        leading: [
          Text(
            widget.countryCode,
            style: AppTypography.body(context).copyWith(
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Container(width: 1, height: 16, color: colors.borderDefault),
        ],
        child: field,
      ),
    );
  }
}
