import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';

/// Phone number field with country dial code prefix (LTR layout).
class AppPhoneInput extends StatefulWidget {
  const AppPhoneInput({
    super.key,
    this.controller,
    this.focusNode,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.countryCode = '+20',
    this.hintText = '10x xxx xxxx',
    this.onChanged,
    this.onValueChange,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String countryCode;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onValueChange;

  @override
  State<AppPhoneInput> createState() => _AppPhoneInputState();
}

class _AppPhoneInputState extends State<AppPhoneInput> {
  late TextEditingController _controller;
  bool _ownsController = false;
  bool _focused = false;

  static String _formatDigits(String digits) {
    final d = digits
        .replaceAll(RegExp(r'\D'), '')
        .substring(0, digits.replaceAll(RegExp(r'\D'), '').length.clamp(0, 10));
    if (d.length <= 3) return d;
    if (d.length <= 6) return '${d.substring(0, 3)} ${d.substring(3)}';
    return '${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
  }

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

  void _handleChanged(String raw) {
    final digits = raw
        .replaceAll(RegExp(r'\D'), '')
        .substring(0, raw.replaceAll(RegExp(r'\D'), '').length.clamp(0, 10));
    final formatted = _formatDigits(digits);
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    widget.onChanged?.call(digits);
    widget.onValueChange?.call(digits);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
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
                widget.countryCode,
                style: AppInputStyles.textStyle(context, widget.size).copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
                color: colors.borderDefault,
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  enabled: !widget.disabled,
                  readOnly: widget.readOnly,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
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
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: _handleChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
