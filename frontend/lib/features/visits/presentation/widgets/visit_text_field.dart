import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_text_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Centered empty-state prompt shown inside visit text inputs.
class VisitEmptyInputPrompt extends StatelessWidget {
  const VisitEmptyInputPrompt({this.icon = Icons.post_add_outlined, this.message = 'Tap to add', super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.tile,
              shape: BoxShape.circle,
              border: Border.all(color: theme.hairlineSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.sm),
              child: Icon(icon, size: 20, color: theme.mutedInk),
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            message,
            style: theme.caption(color: theme.mutedInk),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

typedef _VisitTextInputBuilder = Widget Function(FocusNode focusNode, ValueChanged<String>? onChanged);

/// Visit text input with a centered add prompt when empty and unfocused.
class VisitTextInput extends StatefulWidget {
  const VisitTextInput({
    this.label,
    this.hintText,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.description,
    this.minLines,
    this.maxLines = 1,
    this.expands = false,
    this.fillColor,
    this.textAlignVertical,
    this.focusNode,
    this.onChanged,
    this.prefixIcon,
    this.suffixIcon,
    this.emptyIcon = Icons.post_add_outlined,
    this.emptyPromptText,
    this.showEmptyPrompt = false,
    super.key,
  });

  final String? label;
  final String? hintText;
  final String? description;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool enabled;
  final AppFieldSize size;
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final Color? fillColor;
  final TextAlignVertical? textAlignVertical;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final IconData emptyIcon;
  final String? emptyPromptText;
  final bool showEmptyPrompt;

  @override
  State<VisitTextInput> createState() => _VisitTextInputState();
}

class _VisitTextInputState extends State<VisitTextInput> {
  @override
  Widget build(BuildContext context) {
    return _VisitEmptyInputShell(
      controller: widget.controller,
      enabled: widget.enabled,
      focusNode: widget.focusNode,
      emptyIcon: widget.emptyIcon,
      emptyPromptText: widget.emptyPromptText,
      showEmptyPrompt: widget.showEmptyPrompt,
      onChanged: widget.onChanged,
      builder: (focusNode, onChanged) => AppTextInput(
        label: widget.label,
        hintText: widget.hintText,
        description: widget.description,
        controller: widget.controller,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        enabled: widget.enabled,
        size: widget.size,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        expands: widget.expands,
        fillColor: widget.fillColor,
        textAlignVertical: widget.textAlignVertical,
        focusNode: focusNode,
        onChanged: onChanged,
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.suffixIcon,
      ),
    );
  }
}

/// Visit form text field with a centered add prompt when empty and unfocused.
class VisitTextField extends StatefulWidget {
  const VisitTextField({
    required this.label,
    this.hintText,
    this.controller,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.enabled = true,
    this.size = AppFieldSize.md,
    this.description,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmit,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.inputFormatters,
    this.textAlignVertical,
    this.focusNode,
    this.emptyIcon = Icons.post_add_outlined,
    this.emptyPromptText,
    this.showEmptyPrompt = false,
    super.key,
  });

  final String label;
  final String? hintText;
  final String? description;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool enabled;
  final AppFieldSize size;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmit;
  final TextInputAction? textInputAction;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlignVertical? textAlignVertical;
  final FocusNode? focusNode;
  final IconData emptyIcon;
  final String? emptyPromptText;
  final bool showEmptyPrompt;

  @override
  State<VisitTextField> createState() => _VisitTextFieldState();
}

class _VisitTextFieldState extends State<VisitTextField> {
  @override
  Widget build(BuildContext context) {
    return _VisitEmptyInputShell(
      controller: widget.controller,
      enabled: widget.enabled,
      focusNode: widget.focusNode,
      emptyIcon: widget.emptyIcon,
      emptyPromptText: widget.emptyPromptText,
      showEmptyPrompt: widget.showEmptyPrompt,
      onChanged: widget.onChanged,
      builder: (focusNode, onChanged) => AppTextField(
        label: widget.label,
        hintText: widget.hintText,
        description: widget.description,
        controller: widget.controller,
        validator: widget.validator,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        enabled: widget.enabled,
        size: widget.size,
        maxLines: widget.maxLines,
        onChanged: onChanged,
        onSubmit: widget.onSubmit,
        textInputAction: widget.textInputAction,
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.suffixIcon,
        inputFormatters: widget.inputFormatters,
        textAlignVertical: widget.textAlignVertical,
        focusNode: focusNode,
      ),
    );
  }
}

class _VisitEmptyInputShell extends StatefulWidget {
  const _VisitEmptyInputShell({
    required this.builder,
    required this.controller,
    required this.enabled,
    required this.emptyIcon,
    required this.showEmptyPrompt,
    required this.onChanged,
    this.emptyPromptText,
    this.focusNode,
  });

  final _VisitTextInputBuilder builder;
  final TextEditingController? controller;
  final bool enabled;
  final IconData emptyIcon;
  final String? emptyPromptText;
  final bool showEmptyPrompt;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  State<_VisitEmptyInputShell> createState() => _VisitEmptyInputShellState();
}

class _VisitEmptyInputShellState extends State<_VisitEmptyInputShell> {
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  var _hasText = false;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _syncHasText();
    widget.controller?.addListener(_syncHasText);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _VisitEmptyInputShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_syncHasText);
      widget.controller?.addListener(_syncHasText);
      _syncHasText();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_syncHasText);
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _syncHasText() {
    final hasText = widget.controller?.text.trim().isNotEmpty ?? false;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _onFocusChanged() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  void _handleChanged(String value) {
    if (widget.controller == null) {
      final hasText = value.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    }
    widget.onChanged?.call(value);
  }

  bool get _showPrompt => widget.showEmptyPrompt && widget.enabled && !_hasText && !_focused;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        widget.builder(_focusNode, _handleChanged),
        if (_showPrompt)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.enabled ? _focusNode.requestFocus : null,
              child: Center(
                child: VisitEmptyInputPrompt(
                  icon: widget.emptyIcon,
                  message: widget.emptyPromptText?.trim().isNotEmpty == true
                      ? widget.emptyPromptText!.trim()
                      : 'Tap to add',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
