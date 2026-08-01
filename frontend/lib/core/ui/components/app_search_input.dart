import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_kbd.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Debounced search input with loading state and shortcut hint (web `SearchInput`).
class AppSearchInput extends StatefulWidget {
  const AppSearchInput({
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onValueChange,
    this.placeholder,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.loading = false,
    this.resultCount,
    this.showShortcutHint = true,
    this.debounceMs = 300,
    this.id,
    super.key,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onValueChange;
  final String? placeholder;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final bool loading;
  final int? resultCount;
  final bool showShortcutHint;
  final int debounceMs;
  final String? id;

  @override
  State<AppSearchInput> createState() => _AppSearchInputState();
}

class _AppSearchInputState extends State<AppSearchInput> {
  TextEditingController? _internalController;
  final _focusNode = FocusNode();
  Timer? _debounce;

  TextEditingController get _controller => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = TextEditingController(text: widget.initialValue ?? '');
    } else if (widget.initialValue != null && widget.controller!.text.isEmpty) {
      widget.controller!.text = widget.initialValue!;
    }
    _controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_handleControllerChange);
    _internalController?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (mounted) setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_controller.text.isEmpty) return KeyEventResult.ignored;
    _clear();
    return KeyEventResult.handled;
  }

  void _emit(String value) {
    widget.onValueChange?.call(value);
  }

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: widget.debounceMs), () => _emit(value));
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    _emit('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final metrics = appInputMetrics(context, widget.size);
    final colors = context.appColors;
    final hasValue = _controller.text.isNotEmpty;

    final trailing = <Widget>[
      if (widget.loading)
        SizedBox(
          width: metrics.iconSize,
          height: metrics.iconSize,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.iconMuted),
        )
      else if (hasValue)
        AppPressable(
          onPressed: widget.disabled || widget.readOnly ? null : _clear,
          child: Text(
            'Clear',
            style: AppTypography.caption(context).copyWith(color: colors.textLink),
          ),
        )
      else if (widget.showShortcutHint)
        const AppKbd(child: Text('/')),
    ];

    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: !widget.disabled,
      readOnly: widget.readOnly,
      style: widget.disabled
          ? appInputDisabledTextStyle(context, widget.size)
          : appInputTextStyle(context, widget.size),
      cursorColor: colors.textPrimary,
      decoration: appBareInputDecoration(
        context,
        size: widget.size,
        disabled: widget.disabled,
        hintText: widget.placeholder,
      ),
      onChanged: _handleChanged,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          identifier: widget.id,
          textField: true,
          label: widget.placeholder,
          child: Focus(
            onKeyEvent: _handleKeyEvent,
            child: AppAffixInputWrapper(
              size: widget.size,
              invalid: widget.invalid,
              disabled: widget.disabled,
              readOnly: widget.readOnly,
              focusNode: _focusNode,
              leading: [Icon(Icons.search, size: metrics.iconSize, color: colors.iconMuted)],
              trailing: trailing,
              child: field,
            ),
          ),
        ),
        if (widget.resultCount != null) ...[
          const SizedBox(height: AppSpacing.space1),
          Semantics(
            liveRegion: true,
            child: Text(
              '${widget.resultCount} ${widget.resultCount == 1 ? 'result' : 'results'}',
              style: AppTypography.caption(context).copyWith(
                color: colors.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
