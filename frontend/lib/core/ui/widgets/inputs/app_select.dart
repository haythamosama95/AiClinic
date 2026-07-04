import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_popover_inputs_shared.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_popover.dart';

/// Single option for [AppSelect].
class AppSelectOption<T> {
  const AppSelectOption({
    required this.value,
    required this.label,
    this.icon,
    this.disabled = false,
    this.disabledReason,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool disabled;
  final String? disabledReason;
}

/// Single-choice select with popover option list.
class AppSelect<T> extends StatefulWidget {
  const AppSelect({
    required this.options,
    this.value,
    this.defaultValue,
    this.onChanged,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.placeholder = 'Select an option',
    this.focusNode,
    super.key,
  });

  final List<AppSelectOption<T>> options;
  final T? value;
  final T? defaultValue;
  final ValueChanged<T>? onChanged;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String placeholder;
  final FocusNode? focusNode;

  @override
  State<AppSelect<T>> createState() => _AppSelectState<T>();
}

class _AppSelectState<T> extends State<AppSelect<T>> {
  late AppPopoverController _popoverController;
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  T? _internal;
  int _highlight = 0;
  String _typeahead = '';
  Timer? _typeaheadTimer;

  @override
  void initState() {
    super.initState();
    _popoverController = AppPopoverController();
    _internal = widget.defaultValue;
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
  }

  @override
  void dispose() {
    _typeaheadTimer?.cancel();
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    _popoverController.dispose();
    super.dispose();
  }

  T? get _value => widget.value ?? _internal;

  AppSelectOption<T>? get _selected {
    final current = _value;
    if (current == null) return null;
    for (final opt in widget.options) {
      if (opt.value == current) return opt;
    }
    return null;
  }

  bool get _interactive => !widget.disabled && !widget.readOnly;

  void _select(AppSelectOption<T> option) {
    if (option.disabled) return;
    if (widget.value == null) {
      setState(() => _internal = option.value);
    }
    widget.onChanged?.call(option.value);
    _popoverController.hide();
  }

  void _handleTypeahead(String key) {
    _typeahead += key.toLowerCase();
    _typeaheadTimer?.cancel();
    _typeaheadTimer = Timer(const Duration(milliseconds: 500), () {
      _typeahead = '';
    });
    final idx = widget.options.indexWhere(
      (o) => o.label.toLowerCase().startsWith(_typeahead),
    );
    if (idx >= 0) setState(() => _highlight = idx);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_interactive || event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (!_popoverController.isOpen) _popoverController.show();
      setState(() {
        final delta = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
        var next = _highlight + delta;
        if (next < 0) next = widget.options.length - 1;
        if (next >= widget.options.length) next = 0;
        _highlight = next;
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _popoverController.isOpen) {
      if (_highlight >= 0 && _highlight < widget.options.length) {
        final opt = widget.options[_highlight];
        if (!opt.disabled) _select(opt);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _popoverController.hide();
      return KeyEventResult.handled;
    }

    final char = event.character;
    if (char != null && char.length == 1 && !HardwareKeyboard.instance.isControlPressed) {
      _handleTypeahead(char);
      if (!_popoverController.isOpen) _popoverController.show();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final style = appBareInputTextStyle(
      context,
      size: widget.size,
      disabled: widget.disabled,
      readOnly: widget.readOnly,
    );
    final placeholderStyle = style.copyWith(color: context.colors.textPlaceholder);

    return AppPopover(
      controller: _popoverController,
      matchAnchorWidth: true,
      placement: AppPopoverPlacement.bottomStart,
      onOpenChange: (open) {
        if (open) setState(() {});
      },
      trigger: (context, show, hide, toggle) {
        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKey,
          child: AppInputFrame(
            focusNode: _focusNode,
            size: widget.size,
            invalid: widget.invalid,
            disabled: widget.disabled,
            readOnly: widget.readOnly,
            trailing: AppPopoverChevron(open: _popoverController.isOpen),
            child: AppPressable(
              onTap: _interactive ? toggle : null,
              enabled: _interactive,
              semanticLabel: selected?.label ?? widget.placeholder,
              mouseCursor: _interactive
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  selected?.label ?? widget.placeholder,
                  style: selected == null ? placeholderStyle : style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
      },
      content: (context) {
        return AppPopoverListPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.options.length; i++)
                AppPopoverOptionRow(
                  label: widget.options[i].label,
                  icon: widget.options[i].icon,
                  disabled: widget.options[i].disabled,
                  disabledReason: widget.options[i].disabledReason,
                  highlighted: i == _highlight,
                  selected: widget.options[i].value == _value,
                  showCheck: true,
                  onTap: widget.options[i].disabled
                      ? null
                      : () => _select(widget.options[i]),
                ),
            ],
          ),
        );
      },
    );
  }
}
