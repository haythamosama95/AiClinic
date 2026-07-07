import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Application-owned multiline text input (web `Textarea`).
class AppTextarea extends StatefulWidget {
  const AppTextarea({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.initialValue,
    this.placeholder,
    this.id,
    this.size = AppInputSize.md,
    this.rows = 3,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.autoGrow = false,
    this.maxLength,
    this.showCounter = false,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final String? initialValue;
  final String? placeholder;
  final String? id;
  final AppInputSize size;
  final int rows;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final bool autoGrow;
  final int? maxLength;
  final bool showCounter;

  @override
  State<AppTextarea> createState() => _AppTextareaState();
}

class _AppTextareaState extends State<AppTextarea> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _ownsController = false;
  var _ownsFocusNode = false;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController(text: widget.initialValue);
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppTextarea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ownsController && widget.controller != oldWidget.controller) {
      _controller.removeListener(_handleTextChanged);
    }
    if (_ownsController && widget.initialValue != oldWidget.initialValue && widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _handleTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = appInputMetrics(widget.size);
    final textStyle = appBareInputTextStyle(context, widget.size, disabled: widget.disabled);
    const counterPadding = 28.0;
    final bottomPadding = widget.showCounter && widget.maxLength != null ? counterPadding : 0.0;
    final currentLength = _controller.text.length;

    _controller.removeListener(_handleTextChanged);
    _controller.addListener(_handleTextChanged);

    return Semantics(
      identifier: widget.id,
      textField: true,
      readOnly: widget.readOnly,
      enabled: !widget.disabled,
      maxValueLength: widget.maxLength,
      currentValueLength: currentLength,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standardCurve,
        decoration: appInputDecoration(
          context,
          size: widget.size,
          invalid: widget.invalid,
          disabled: widget.disabled,
          readOnly: widget.readOnly,
          focused: _focused,
        ),
        child: Stack(
          children: [
            appWrapMaterialInput(
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: !widget.disabled,
                readOnly: widget.readOnly,
                maxLines: widget.autoGrow ? null : widget.rows,
                minLines: widget.rows,
                maxLength: widget.maxLength,
                maxLengthEnforcement: widget.maxLength != null ? MaxLengthEnforcement.enforced : null,
                style: textStyle,
                cursorColor: colors.textPrimary,
                onChanged: widget.onChanged,
                decoration:
                    appBareInputDecoration(
                      context,
                      size: widget.size,
                      disabled: widget.disabled,
                      hintText: widget.placeholder,
                    ).copyWith(
                      contentPadding: EdgeInsets.fromLTRB(
                        metrics.horizontalPadding,
                        AppSpacing.space2,
                        metrics.horizontalPadding,
                        AppSpacing.space2 + bottomPadding,
                      ),
                      counterText: widget.showCounter ? '' : null,
                    ),
              ),
            ),
            if (widget.showCounter && widget.maxLength != null)
              PositionedDirectional(
                end: AppSpacing.space3,
                bottom: AppSpacing.space2,
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '$currentLength/${widget.maxLength}',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colors.textTertiary, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
