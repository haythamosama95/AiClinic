import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';

/// Single-line text field with optional affixes and clear action.
class AppTextInput extends StatefulWidget {
  const AppTextInput({
    super.key,
    this.controller,
    this.focusNode,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.hintText,
    this.leadingIcon,
    this.trailingIcon,
    this.prefix,
    this.suffix,
    this.showClear = false,
    this.onClear,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.maxLines = 1,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.style,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? hintText;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final String? prefix;
  final String? suffix;
  final bool showClear;
  final VoidCallback? onClear;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  State<AppTextInput> createState() => _AppTextInputState();
}

class _AppTextInputState extends State<AppTextInput> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _initFocusNode();
  }

  void _initFocusNode() {
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(AppTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_handleFocusChange);
      if (_ownsFocusNode) _focusNode.dispose();
      _initFocusNode();
    }
  }

  void _handleFocusChange() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  bool get _hasAffix =>
      widget.leadingIcon != null ||
      widget.trailingIcon != null ||
      widget.prefix != null ||
      widget.suffix != null ||
      widget.showClear;

  bool get _canClear {
    if (!widget.showClear || widget.disabled || widget.readOnly) return false;
    final text = widget.controller?.text ?? '';
    return text.isNotEmpty;
  }

  TextStyle _textStyle(BuildContext context) {
    final colors = context.colors;
    final base = widget.style ?? AppInputStyles.textStyle(context, widget.size);
    return base.copyWith(
      color: widget.disabled ? colors.textDisabled : colors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  InputDecoration _bareDecoration() {
    return const InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _icon(IconData icon) {
    return Icon(icon, size: 18, color: context.colors.iconMuted);
  }

  Widget _buildField({required bool bare}) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: !widget.disabled,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      inputFormatters: widget.inputFormatters,
      textAlign: widget.textAlign,
      autocorrect: false,
      enableSuggestions: false,
      spellCheckConfiguration: SpellCheckConfiguration.disabled(),
      style: _textStyle(context),
      cursorColor: context.colors.borderFocus,
      decoration: bare
          ? _bareDecoration().copyWith(
              hintText: widget.hintText,
              hintStyle: _textStyle(
                context,
              ).copyWith(color: context.colors.textPlaceholder),
            )
          : AppInputStyles.bareInputDecoration(
              context,
              hintText: widget.hintText,
              disabled: widget.disabled,
            ),
      onChanged: (value) {
        widget.onChanged?.call(value);
        if (widget.showClear) setState(() {});
      },
      onSubmitted: widget.onSubmitted,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAffix) {
      return Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
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
          child: _buildField(bare: true),
        ),
      );
    }

    final colors = context.colors;

    return Focus(
      onFocusChange: (focused) => setState(() => _focused = focused),
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
            if (widget.leadingIcon != null) ...[
              _icon(widget.leadingIcon!),
              const SizedBox(width: AppSpacing.s2),
            ],
            if (widget.prefix != null) ...[
              Text(
                widget.prefix!,
                style: AppInputStyles.affixTextStyle(
                  context,
                  widget.size,
                ).copyWith(color: colors.textTertiary),
              ),
              const SizedBox(width: AppSpacing.s2),
            ],
            Expanded(child: _buildField(bare: true)),
            if (widget.suffix != null) ...[
              const SizedBox(width: AppSpacing.s2),
              Text(
                widget.suffix!,
                style: AppInputStyles.affixTextStyle(
                  context,
                  widget.size,
                ).copyWith(color: colors.textTertiary),
              ),
            ],
            if (_canClear)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: colors.iconMuted),
                onPressed: widget.onClear,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Clear',
              )
            else if (widget.trailingIcon != null) ...[
              const SizedBox(width: AppSpacing.s1),
              _icon(widget.trailingIcon!),
            ],
          ],
        ),
      ),
    );
  }
}
