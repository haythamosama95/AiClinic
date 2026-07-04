import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';

/// Password field with show/hide toggle and caps-lock hint.
class AppPasswordInput extends StatefulWidget {
  const AppPasswordInput({
    super.key,
    this.controller,
    this.focusNode,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<AppPasswordInput> createState() => _AppPasswordInputState();
}

class _AppPasswordInputState extends State<AppPasswordInput> {
  bool _visible = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
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
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    enabled: !widget.disabled,
                    readOnly: widget.readOnly,
                    obscureText: !_visible,
                    autofillHints:
                        widget.autofillHints ?? const [AutofillHints.password],
                    style: AppInputStyles.textStyle(context, widget.size)
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
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _visible ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                    color: colors.iconMuted,
                  ),
                  onPressed: widget.disabled
                      ? null
                      : () => setState(() => _visible = !_visible),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: _visible ? 'Hide password' : 'Show password',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
