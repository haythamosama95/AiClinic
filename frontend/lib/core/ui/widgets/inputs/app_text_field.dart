import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';

/// Single-line text input with optional icons, affixes, and clear action.
class AppTextField extends StatefulWidget {
  const AppTextField({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onClear,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.obscureText = false,
    this.hintText,
    this.leadingIcon,
    this.trailingIcon,
    this.prefix,
    this.suffix,
    this.showClear = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final bool obscureText;
  final String? hintText;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final String? prefix;
  final String? suffix;
  final bool showClear;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final int maxLines;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
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
      _controller = TextEditingController();
      _ownsController = true;
    }
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _controller.addListener(_handleTextChange);
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_handleTextChange);
      if (_ownsController) {
        _controller.dispose();
      }
      if (widget.controller != null) {
        _controller = widget.controller!;
        _ownsController = false;
      } else {
        _controller = TextEditingController(text: oldWidget.controller?.text);
        _ownsController = true;
      }
      _controller.addListener(_handleTextChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      if (widget.focusNode != null) {
        _focusNode = widget.focusNode!;
        _ownsFocusNode = false;
      } else {
        _focusNode = FocusNode();
        _ownsFocusNode = true;
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChange);
    if (_ownsController) {
      _controller.dispose();
    }
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleTextChange() {
    if (mounted) setState(() {});
  }

  bool get _canClear =>
      widget.showClear &&
      !widget.disabled &&
      !widget.readOnly &&
      _controller.text.isNotEmpty;

  bool get _hasAffixes =>
      widget.leadingIcon != null ||
      widget.trailingIcon != null ||
      widget.prefix != null ||
      widget.suffix != null ||
      widget.showClear;

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  Widget _buildField({required bool wrapped}) {
    final style = appBareInputTextStyle(
      context,
      size: widget.size,
      disabled: widget.disabled,
      readOnly: widget.readOnly,
    );

    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: !widget.disabled,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      style: style,
      textAlign: widget.textAlign,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      inputFormatters: widget.inputFormatters,
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      decoration: appBareInputDecoration(
        context: context,
        size: widget.size,
        hintText: widget.hintText,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
      ),
      cursorColor: context.colors.borderFocus,
    );

    if (!wrapped) {
      return AppInputFrame(
        focusNode: _focusNode,
        size: widget.size,
        invalid: widget.invalid,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
        child: field,
      );
    }

    return AppInputFrame(
      focusNode: _focusNode,
      size: widget.size,
      invalid: widget.invalid,
      disabled: widget.disabled,
      readOnly: widget.readOnly,
      leading: _buildLeading(),
      trailing: _buildTrailing(),
      child: field,
    );
  }

  Widget? _buildLeading() {
    final children = <Widget>[];
    if (widget.leadingIcon != null) {
      children.add(AppInputIconSlot(icon: widget.leadingIcon!));
    }
    if (widget.prefix != null) {
      children.add(AppInputAffix(label: widget.prefix!, size: widget.size));
    }
    if (children.isEmpty) return null;
    if (children.length == 1) return children.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.s2),
          children[i],
        ],
      ],
    );
  }

  Widget? _buildTrailing() {
    if (_canClear) {
      return AppInputInlineButton(
        icon: LucideIcons.x,
        semanticLabel: 'Clear',
        onPressed: _clear,
      );
    }
    if (widget.suffix != null) {
      return AppInputAffix(label: widget.suffix!, size: widget.size);
    }
    if (widget.trailingIcon != null) {
      return AppInputIconSlot(icon: widget.trailingIcon!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _buildField(wrapped: _hasAffixes);
  }
}
