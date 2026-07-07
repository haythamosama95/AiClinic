import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Whether an input uses the affix wrapper layout (web `hasAffix` check).
bool appAffixInputHasAffixes({
  Widget? leadingIcon,
  Widget? trailingIcon,
  String? prefix,
  String? suffix,
  bool showClear = false,
  List<Widget> leading = const [],
  List<Widget> trailing = const [],
}) {
  return leadingIcon != null ||
      trailingIcon != null ||
      prefix != null ||
      suffix != null ||
      showClear ||
      leading.isNotEmpty ||
      trailing.isNotEmpty;
}

/// Shared affix shell for [AppTextInput], [AppMoneyField], and similar controls.
class AppAffixInputWrapper extends StatefulWidget {
  const AppAffixInputWrapper({
    required this.child,
    required this.size,
    this.focusNode,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.forceLtr = false,
    this.leading = const [],
    this.trailing = const [],
    this.prefix,
    this.suffix,
    super.key,
  });

  final Widget child;
  final AppInputSize size;
  final FocusNode? focusNode;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final bool forceLtr;
  final List<Widget> leading;
  final List<Widget> trailing;
  final String? prefix;
  final String? suffix;

  @override
  State<AppAffixInputWrapper> createState() => _AppAffixInputWrapperState();
}

class _AppAffixInputWrapperState extends State<AppAffixInputWrapper> {
  late FocusNode _focusNode;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppAffixInputWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode
        ..removeListener(_handleFocusChange)
        ..dispose();
    } else {
      _focusNode.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused && mounted) {
      setState(() => _focused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = appInputMetrics(context, widget.size);
    final affixStyle = widget.disabled
        ? appBareInputTextStyle(context, widget.size, disabled: true)
        : metrics.affixTextStyle ?? appInputAffixTextStyle(context, widget.size);

    Widget shell = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      height: metrics.height,
      padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
      decoration: appInputDecoration(
        context,
        size: widget.size,
        invalid: widget.invalid,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
        focused: _focused,
      ),
      child: Row(
        children: [
          for (final item in widget.leading) ...[item, SizedBox(width: metrics.gap)],
          if (widget.prefix != null) ...[Text(widget.prefix!, style: affixStyle), SizedBox(width: metrics.gap)],
          Expanded(child: appCenterInputField(widget.child)),
          if (widget.suffix != null) ...[SizedBox(width: metrics.gap), Text(widget.suffix!, style: affixStyle)],
          for (final item in widget.trailing) ...[SizedBox(width: metrics.gap), item],
        ],
      ),
    );

    if (widget.forceLtr) {
      shell = Directionality(textDirection: TextDirection.ltr, child: shell);
    }

    return shell;
  }
}

/// Application-owned text input (web `TextInput`).
class AppTextInput extends StatefulWidget {
  const AppTextInput({
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onClear,
    this.placeholder,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.leadingIcon,
    this.trailingIcon,
    this.prefix,
    this.suffix,
    this.showClear = false,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.shellDecoration,
    super.key,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final String? placeholder;
  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final String? prefix;
  final String? suffix;
  final bool showClear;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;

  /// Optional shell decoration override (e.g. AI panel violet focus ring).
  final BoxDecoration Function(BuildContext context, {required bool focused})? shellDecoration;

  @override
  State<AppTextInput> createState() => _AppTextInputState();
}

class _AppTextInputState extends State<AppTextInput> {
  TextEditingController? _internalController;
  final _focusNode = FocusNode();
  var _focused = false;

  TextEditingController get _controller => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = TextEditingController(text: widget.initialValue);
    }
    _focusNode.addListener(_handleFocusChange);
    _controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant AppTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleControllerChange);
      if (widget.controller == null) {
        _internalController ??= TextEditingController(text: widget.initialValue);
      } else {
        _internalController?.dispose();
        _internalController = null;
      }
      _controller.addListener(_handleControllerChange);
    }
    if (widget.initialValue != oldWidget.initialValue &&
        widget.controller == null &&
        _controller.text.isEmpty &&
        widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChange);
    _internalController?.dispose();
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused && mounted) {
      setState(() => _focused = focused);
    }
  }

  void _handleControllerChange() {
    if (mounted) setState(() {});
  }

  bool get _hasAffixes => appAffixInputHasAffixes(
    leadingIcon: widget.leadingIcon,
    trailingIcon: widget.trailingIcon,
    prefix: widget.prefix,
    suffix: widget.suffix,
    showClear: widget.showClear,
  );

  bool get _canClear => widget.showClear && !widget.disabled && !widget.readOnly && _controller.text.isNotEmpty;

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final metrics = appInputMetrics(context, widget.size);
    final textStyle = appBareInputTextStyle(context, widget.size, disabled: widget.disabled);

    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: !widget.disabled,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      style: textStyle,
      cursorColor: context.appColors.textPrimary,
      onChanged: widget.onChanged,
      decoration: appBareInputDecoration(
        context,
        size: widget.size,
        disabled: widget.disabled,
        hintText: widget.placeholder,
      ),
    );

    BoxDecoration resolveShellDecoration() {
      if (widget.shellDecoration != null) {
        return widget.shellDecoration!(context, focused: _focused);
      }
      return appInputDecoration(
        context,
        size: widget.size,
        invalid: widget.invalid,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
        focused: _focused,
      );
    }

    Widget result;
    if (!_hasAffixes) {
      result = AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: metrics.height,
        padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
        decoration: resolveShellDecoration(),
        child: appCenterInputField(field),
      );
    } else {
      final trailing = <Widget>[];
      if (_canClear) {
        trailing.add(
          Semantics(
            button: true,
            label: 'Clear',
            child: AppPressable(
              onPressed: _clear,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space05),
                child: Icon(Icons.close, size: metrics.iconSize, color: context.appColors.iconMuted),
              ),
            ),
          ),
        );
      } else if (widget.trailingIcon != null) {
        trailing.add(
          IconTheme(
            data: IconThemeData(size: metrics.iconSize, color: context.appColors.iconMuted),
            child: widget.trailingIcon!,
          ),
        );
      }

      result = AppAffixInputWrapper(
        focusNode: _focusNode,
        size: widget.size,
        invalid: widget.invalid,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
        prefix: widget.prefix,
        suffix: widget.suffix,
        leading: widget.leadingIcon == null
            ? const []
            : [
                IconTheme(
                  data: IconThemeData(size: metrics.iconSize, color: context.appColors.iconMuted),
                  child: widget.leadingIcon!,
                ),
              ],
        trailing: trailing,
        child: field,
      );
    }

    return Semantics(
      textField: true,
      identifier: widget.id,
      enabled: !widget.disabled,
      readOnly: widget.readOnly,
      obscured: widget.obscureText,
      hint: widget.invalid ? 'Invalid' : null,
      child: result,
    );
  }
}
