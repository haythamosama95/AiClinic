import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Single option for [AppSelect] (web `SelectOption`).
@immutable
class AppSelectOption {
  const AppSelectOption({required this.value, required this.label, this.disabled = false, this.disabledReason});

  final String value;
  final String label;
  final bool disabled;
  final String? disabledReason;
}

/// Application-owned single-choice dropdown (web `Select`).
class AppSelect extends StatefulWidget {
  const AppSelect({
    required this.options,
    this.value,
    this.initialValue,
    this.onChanged,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.placeholder = 'Select an option',
    this.ariaLabelledBy,
    this.ariaDescribedBy,
    super.key,
  });

  final List<AppSelectOption> options;
  final String? value;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String placeholder;
  final String? ariaLabelledBy;
  final String? ariaDescribedBy;

  @override
  State<AppSelect> createState() => _AppSelectState();
}

class _AppSelectState extends State<AppSelect> {
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _optionKeys = <GlobalKey>[];

  var _open = false;
  var _focused = false;
  var _highlight = 0;
  String? _internalValue;
  String _typeahead = '';
  Timer? _typeaheadTimer;

  bool get _isControlled => widget.value != null;

  String get _value => _isControlled ? widget.value! : (_internalValue ?? '');

  AppSelectOption? get _selected {
    for (final opt in widget.options) {
      if (opt.value == _value) return opt;
    }
    return null;
  }

  bool get _interactionDisabled => widget.disabled || widget.readOnly;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.initialValue;
    _focusNode.addListener(_handleFocusChange);
    _syncOptionKeys();
  }

  @override
  void didUpdateWidget(covariant AppSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      _syncOptionKeys();
    }
    if (widget.initialValue != oldWidget.initialValue &&
        !_isControlled &&
        (_internalValue == null || _internalValue!.isEmpty)) {
      _internalValue = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _typeaheadTimer?.cancel();
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _syncOptionKeys() {
    _optionKeys
      ..clear()
      ..addAll(List.generate(widget.options.length, (_) => GlobalKey()));
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused && mounted) {
      setState(() => _focused = focused);
    }
  }

  void _setOpen(bool next) {
    if (_interactionDisabled) return;
    if (_open == next) return;
    setState(() {
      _open = next;
      if (next) {
        final selectedIndex = widget.options.indexWhere((o) => o.value == _value);
        _highlight = selectedIndex >= 0 ? selectedIndex : 0;
      }
    });
    if (next) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlight());
    }
  }

  void _select(String next) {
    if (!_isControlled) {
      setState(() => _internalValue = next);
    }
    widget.onChanged?.call(next);
    _setOpen(false);
  }

  void _handleTypeahead(String key) {
    _typeaheadTimer?.cancel();
    _typeahead += key.toLowerCase();
    _typeaheadTimer = Timer(const Duration(milliseconds: 500), () => _typeahead = '');

    final idx = widget.options.indexWhere((o) => o.label.toLowerCase().startsWith(_typeahead));
    if (idx >= 0) {
      setState(() => _highlight = idx);
      _scrollToHighlight();
    }
  }

  void _scrollToHighlight() {
    if (!_scrollController.hasClients) return;
    final key = _optionKeys.elementAtOrNull(_highlight);
    final context = key?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, duration: AppMotion.fast, curve: AppMotion.standardCurve, alignment: 0.5);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_interactionDisabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      if (!_open) _setOpen(true);
      setState(() {
        final delta = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
        var next = _highlight + delta;
        if (next < 0) next = widget.options.length - 1;
        if (next >= widget.options.length) next = 0;
        _highlight = next;
      });
      _scrollToHighlight();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter && _open) {
      final opt = widget.options.elementAtOrNull(_highlight);
      if (opt != null && !opt.disabled) {
        _select(opt.value);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_open) {
        _setOpen(false);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.space) {
      if (!_open) {
        _setOpen(true);
        return KeyEventResult.handled;
      }
    }

    final label = event.character;
    if (label != null &&
        label.length == 1 &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      if (!_open) _setOpen(true);
      _handleTypeahead(label);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = appInputMetrics(context, widget.size);
    final selected = _selected;
    final displayLabel = selected?.label ?? widget.placeholder;
    final showPlaceholder = selected == null;

    final listbox = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
        shrinkWrap: true,
        children: [for (var i = 0; i < widget.options.length; i++) _buildOption(context, i)],
      ),
    );

    final estimatedListHeight = math.min(240.0, widget.options.length * metrics.height + AppSpacing.space2);

    return Semantics(
      button: true,
      enabled: !widget.disabled,
      identifier: widget.id,
      label: widget.placeholder,
      value: selected?.label,
      expanded: _open,
      child: AppPopover(
        open: _open && !_interactionDisabled,
        onOpenChange: _setOpen,
        estimatedContentHeight: estimatedListHeight,
        child: listbox,
        triggerBuilder: (context, isOpen, onToggle) => Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: AppPressable(
            enabled: !_interactionDisabled,
            onPressed: onToggle,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.standardCurve,
              height: metrics.height,
              padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
              decoration: appInputDecoration(
                context,
                size: widget.size,
                invalid: widget.invalid,
                disabled: widget.disabled,
                readOnly: widget.readOnly,
                focused: _focused || isOpen,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayLabel,
                      style: (metrics.textStyle ?? AppTypography.body(context)).copyWith(
                        color: showPlaceholder
                            ? colors.textPlaceholder
                            : (widget.disabled ? colors.textDisabled : colors.textPrimary),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: metrics.gap),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: AppMotion.fast,
                    curve: AppMotion.standardCurve,
                    child: Icon(Icons.keyboard_arrow_down, size: metrics.iconSize, color: colors.iconMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption(BuildContext context, int index) {
    final colors = context.appColors;
    final opt = widget.options[index];
    final isSelected = opt.value == _value;
    final isHighlighted = index == _highlight;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warningColor = isDark ? AppColorPrimitives.statusWarningFgDark : AppColorPrimitives.amber700;

    Color background;
    if (isSelected) {
      background = colors.surfaceSelected;
    } else if (isHighlighted) {
      background = colors.surfaceHover;
    } else {
      background = Colors.transparent;
    }

    return KeyedSubtree(
      key: _optionKeys[index],
      child: Semantics(
        button: true,
        selected: isSelected,
        enabled: !opt.disabled,
        label: opt.disabled && opt.disabledReason != null ? '${opt.label}. ${opt.disabledReason}' : opt.label,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: opt.disabled ? null : () => _select(opt.value),
            onHover: opt.disabled ? null : (_) => setState(() => _highlight = index),
            child: Opacity(
              opacity: opt.disabled ? 0.6 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            opt.label,
                            style: AppTypography.body(
                              context,
                            ).copyWith(color: opt.disabled ? colors.textDisabled : colors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (opt.disabled && opt.disabledReason != null)
                            Text(
                              opt.disabledReason!,
                              style: AppTypography.caption(context).copyWith(color: warningColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (isSelected) Icon(Icons.check, size: 16, color: colors.actionPrimary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
