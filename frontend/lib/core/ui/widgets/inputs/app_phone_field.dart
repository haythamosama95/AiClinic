import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';

/// Egypt-local phone input with country code and live formatting.
class AppPhoneField extends StatefulWidget {
  const AppPhoneField({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onValueChange,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.countryCode = '+20',
    this.value,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onValueChange;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String countryCode;
  final String? value;

  @override
  State<AppPhoneField> createState() => _AppPhoneFieldState();
}

class _AppPhoneFieldState extends State<AppPhoneField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  String _internalDigits = '';

  static String formatPhoneDigits(String digits) {
    final d = digits.replaceAll(RegExp(r'\D'), '');
    final limited = d.length > 10 ? d.substring(0, 10) : d;
    if (limited.length <= 3) return limited;
    if (limited.length <= 6) {
      return '${limited.substring(0, 3)} ${limited.substring(3)}';
    }
    return '${limited.substring(0, 3)} ${limited.substring(3, 6)} ${limited.substring(6)}';
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.value ?? '';
    _internalDigits = initial.replaceAll(RegExp(r'\D'), '');
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController(
        text: formatPhoneDigits(_internalDigits),
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
  void didUpdateWidget(covariant AppPhoneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != null) {
      _internalDigits = widget.value!.replaceAll(RegExp(r'\D'), '');
      _controller.text = formatPhoneDigits(_internalDigits);
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

  void _handleChanged(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 10 ? digits.substring(0, 10) : digits;
    final formatted = formatPhoneDigits(limited);
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    if (widget.value == null) {
      _internalDigits = limited;
    }
    widget.onChanged?.call(limited);
    widget.onValueChange?.call(limited);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return AppInputFrame(
      focusNode: _focusNode,
      size: widget.size,
      invalid: widget.invalid,
      disabled: widget.disabled,
      readOnly: widget.readOnly,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.countryCode,
            style: typography.tabular(
              widget.size.textStyle(context).copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Container(
            width: AppSpacing.sPx,
            height: AppSpacing.s4,
            color: colors.borderDefault,
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: !widget.disabled,
        readOnly: widget.readOnly,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d\s]')),
        ],
        style: appBareInputTextStyle(
          context,
          size: widget.size,
          disabled: widget.disabled,
          readOnly: widget.readOnly,
        ),
        onChanged: _handleChanged,
        decoration: appBareInputDecoration(
          context: context,
          size: widget.size,
          hintText: '10x xxx xxxx',
          disabled: widget.disabled,
          readOnly: widget.readOnly,
        ),
        cursorColor: colors.borderFocus,
      ),
    );
  }
}
