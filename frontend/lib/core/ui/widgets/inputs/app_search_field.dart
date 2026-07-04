import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/app_spinner.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';

/// Debounced search input with loading, clear, and optional result count.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onValueChange,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.hintText,
    this.loading = false,
    this.resultCount,
    this.showShortcutHint = true,
    this.debounceMs = 300,
    this.value,
    this.defaultValue,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onValueChange;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? hintText;
  final bool loading;
  final int? resultCount;
  final bool showShortcutHint;
  final int debounceMs;
  final String? value;
  final String? defaultValue;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  String _internal = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _internal = widget.value ?? widget.defaultValue ?? '';
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController(text: _internal);
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
  void didUpdateWidget(covariant AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != null) {
      _controller.text = widget.value!;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  bool get _isControlled => widget.value != null;

  String get _currentValue =>
      _isControlled ? widget.value! : _controller.text;

  void _emit(String next) {
    if (!_isControlled) {
      setState(() => _internal = next);
    }
    widget.onValueChange?.call(next);
  }

  void _handleChanged(String next) {
    widget.onChanged?.call(next);
    _debounce?.cancel();
    _debounce = Timer(
      Duration(milliseconds: widget.debounceMs),
      () => _emit(next),
    );
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    _emit('');
    widget.onChanged?.call('');
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _focusNode.hasFocus) {
      _clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final hasValue = _currentValue.isNotEmpty;

    Widget? trailing;
    if (widget.loading) {
      trailing = const AppSpinner(size: AppSpinnerSize.sm);
    } else if (hasValue) {
      trailing = AppInputInlineButton(
        icon: LucideIcons.x,
        semanticLabel: 'Clear search',
        onPressed: widget.disabled || widget.readOnly ? null : _clear,
      );
    } else if (widget.showShortcutHint) {
      trailing = const AppInputShortcutHint(label: '/');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          onKeyEvent: _handleKeyEvent,
          child: AppInputFrame(
            focusNode: _focusNode,
            size: widget.size,
            invalid: widget.invalid,
            disabled: widget.disabled,
            readOnly: widget.readOnly,
            leading: const AppInputIconSlot(icon: LucideIcons.search),
            trailing: trailing,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: !widget.disabled,
              readOnly: widget.readOnly,
              style: appBareInputTextStyle(
                context,
                size: widget.size,
                disabled: widget.disabled,
                readOnly: widget.readOnly,
              ),
              onChanged: _handleChanged,
              decoration: appBareInputDecoration(
                context: context,
                size: widget.size,
                hintText: widget.hintText,
                disabled: widget.disabled,
                readOnly: widget.readOnly,
              ),
              cursorColor: colors.borderFocus,
            ),
          ),
        ),
        if (widget.resultCount != null) ...[
          const SizedBox(height: AppSpacing.s1),
          Semantics(
            liveRegion: true,
            child: Text(
              '${widget.resultCount} ${widget.resultCount == 1 ? 'result' : 'results'}',
              style: typography.tabular(
                typography.caption.copyWith(color: colors.textTertiary),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
