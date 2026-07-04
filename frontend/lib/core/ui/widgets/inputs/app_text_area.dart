import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';

/// Multi-line text input with optional auto-grow and character counter.
class AppTextArea extends StatefulWidget {
  const AppTextArea({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.hintText,
    this.minRows = 3,
    this.autoGrow = false,
    this.maxLength,
    this.showCounter = false,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? hintText;
  final int minRows;
  final bool autoGrow;
  final int? maxLength;
  final bool showCounter;

  @override
  State<AppTextArea> createState() => _AppTextAreaState();
}

class _AppTextAreaState extends State<AppTextArea> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  static const double _minHeightFactor = 2;

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
  void didUpdateWidget(covariant AppTextArea oldWidget) {
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

  double get _minHeight => AppSpacing.s8 * _minHeightFactor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final showCounter = widget.showCounter && widget.maxLength != null;
    final counterPadding = showCounter ? AppSpacing.s8 - AppSpacing.s1 : 0.0;

    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: !widget.disabled,
      readOnly: widget.readOnly,
      maxLines: widget.autoGrow ? null : widget.minRows,
      minLines: widget.autoGrow ? widget.minRows : null,
      maxLength: widget.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      buildCounter: (
        context, {
        required currentLength,
        required isFocused,
        required maxLength,
      }) =>
          null,
      style: appBareInputTextStyle(
        context,
        size: widget.size,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
      ),
      onChanged: widget.onChanged,
      decoration: appBareInputDecoration(
        context: context,
        size: widget.size,
        hintText: widget.hintText,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
      ).copyWith(
        contentPadding: EdgeInsets.only(
          top: AppSpacing.s2,
          bottom: AppSpacing.s2 + counterPadding,
        ),
      ),
      cursorColor: colors.borderFocus,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
    );

    return Stack(
      children: [
        AppInputFrame(
          focusNode: _focusNode,
          size: widget.size,
          invalid: widget.invalid,
          disabled: widget.disabled,
          readOnly: widget.readOnly,
          minHeight: _minHeight,
          padding: EdgeInsetsDirectional.fromSTEB(
            widget.size.padding.start,
            AppSpacing.s2,
            widget.size.padding.end,
            AppSpacing.s2,
          ),
          child: field,
        ),
        if (showCounter)
          PositionedDirectional(
            end: AppSpacing.s3,
            bottom: AppSpacing.s2,
            child: Text(
              '${_controller.text.characters.length}/${widget.maxLength}',
              style: typography.tabular(
                typography.caption.copyWith(color: colors.textTertiary),
              ),
            ),
          ),
      ],
    );
  }
}
