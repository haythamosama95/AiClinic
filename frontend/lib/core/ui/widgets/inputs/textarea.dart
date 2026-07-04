import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';

/// Multi-line text field with optional auto-grow and character counter.
class AppTextarea extends StatefulWidget {
  const AppTextarea({
    super.key,
    this.controller,
    this.focusNode,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.hintText,
    this.minLines = 3,
    this.maxLines = 8,
    this.autoGrow = false,
    this.maxLength,
    this.showCounter = false,
    this.onChanged,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? hintText;
  final int minLines;
  final int maxLines;
  final bool autoGrow;
  final int? maxLength;
  final bool showCounter;
  final ValueChanged<String>? onChanged;

  @override
  State<AppTextarea> createState() => _AppTextareaState();
}

class _AppTextareaState extends State<AppTextarea> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final length = widget.controller?.text.length ?? 0;

    return Stack(
      children: [
        Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3,
              vertical: AppSpacing.s2,
            ),
            decoration: AppInputStyles.wrapperDecoration(
              context,
              size: widget.size,
              invalid: widget.invalid,
              disabled: widget.disabled,
              readOnly: widget.readOnly,
              focused: _focused,
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: !widget.disabled,
              readOnly: widget.readOnly,
              minLines: widget.minLines,
              maxLines: widget.autoGrow ? null : widget.maxLines,
              maxLength: widget.maxLength,
              buildCounter: widget.showCounter && widget.maxLength != null
                  ? (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null
                  : null,
              style: AppInputStyles.textStyle(context, widget.size).copyWith(
                color: widget.disabled
                    ? colors.textDisabled
                    : colors.textPrimary,
              ),
              cursorColor: colors.borderFocus,
              decoration: AppInputStyles.bareInputDecoration(
                context,
                hintText: widget.hintText,
                disabled: widget.disabled,
              ),
              onChanged: widget.onChanged,
            ),
          ),
        ),
        if (widget.showCounter && widget.maxLength != null)
          Positioned(
            right: context.isRtl ? null : AppSpacing.s3,
            left: context.isRtl ? AppSpacing.s3 : null,
            bottom: AppSpacing.s2,
            child: Text(
              '$length/${widget.maxLength}',
              style: typography.caption.copyWith(
                color: colors.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}
