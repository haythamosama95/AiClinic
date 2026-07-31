import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Application-owned password input (web `PasswordInput`).
class AppPasswordInput extends StatefulWidget {
  const AppPasswordInput({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.initialValue,
    this.placeholder,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final String? initialValue;
  final String? placeholder;
  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;

  @override
  State<AppPasswordInput> createState() => _AppPasswordInputState();
}

class _AppPasswordInputState extends State<AppPasswordInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _ownsController = false;
  var _ownsFocusNode = false;
  var _focused = false;
  var _visible = false;
  var _capsLock = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController(text: widget.initialValue);
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _updateCapsLock();
  }

  @override
  void didUpdateWidget(covariant AppPasswordInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only apply external initialValue before the user types. Reassigning
    // controller.text on every parent rebuild (e.g. staff setup draft sync)
    // resets selection and drops focus after each keystroke.
    if (_ownsController &&
        widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != null &&
        _controller.text.isEmpty) {
      _controller.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    _updateCapsLock();
    return false;
  }

  void _updateCapsLock() {
    final enabled = HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    if (enabled != _capsLock && mounted) {
      setState(() => _capsLock = enabled);
    }
  }

  void _handleFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  Color _warningColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColorPrimitives.statusWarningFgDark : AppColorPrimitives.amber700;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = appInputMetrics(widget.size);
    final textStyle = appBareInputTextStyle(context, widget.size, disabled: widget.disabled);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standardCurve,
          height: metrics.height,
          decoration: appInputWrapperDecoration(
            context,
            size: widget.size,
            invalid: widget.invalid,
            disabled: widget.disabled,
            readOnly: widget.readOnly,
            focused: _focused,
          ),
          padding: EdgeInsetsDirectional.only(start: metrics.horizontalPadding, end: AppSpacing.space1),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  identifier: widget.id,
                  textField: true,
                  readOnly: widget.readOnly,
                  enabled: !widget.disabled,
                  child: appWrapMaterialInput(
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: !widget.disabled,
                      readOnly: widget.readOnly,
                      obscureText: !_visible,
                      style: textStyle,
                      cursorColor: colors.textPrimary,
                      onChanged: widget.onChanged,
                      decoration: appBareInputDecoration(
                        context,
                        size: widget.size,
                        disabled: widget.disabled,
                        hintText: widget.placeholder,
                      ),
                    ),
                  ),
                ),
              ),
              _RevealToggle(
                visible: _visible,
                disabled: widget.disabled,
                onPressed: widget.disabled ? null : () => setState(() => _visible = !_visible),
              ),
            ],
          ),
        ),
        if (_capsLock) ...[
          const SizedBox(height: AppSpacing.space1),
          Semantics(
            liveRegion: true,
            child: Text(
              'Caps Lock is on',
              style: AppTypography.caption(context).copyWith(color: _warningColor(context)),
            ),
          ),
        ],
      ],
    );
  }
}

class _RevealToggle extends StatelessWidget {
  const _RevealToggle({required this.visible, required this.disabled, this.onPressed});

  final bool visible;
  final bool disabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: visible ? 'Hide password' : 'Show password',
      toggled: visible,
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 16,
            color: disabled ? colors.textDisabled : colors.iconMuted,
          ),
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints.tightFor(width: 24, height: 24),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}
