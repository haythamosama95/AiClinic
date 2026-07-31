import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Layout direction for [AppRadioGroup] (web `orientation`).
enum AppRadioGroupOrientation { vertical, horizontal }

/// A single option in [AppRadioGroup] (web `RadioOption`).
class AppRadioOption {
  const AppRadioOption({
    required this.value,
    required this.label,
    this.disabled = false,
  });

  final String value;
  final String label;
  final bool disabled;
}

/// Application-owned radio group (web `RadioGroup`).
class AppRadioGroup extends StatefulWidget {
  const AppRadioGroup({
    required this.options,
    super.key,
    this.value,
    this.initialValue,
    this.onChanged,
    this.orientation = AppRadioGroupOrientation.vertical,
    this.disabled = false,
    this.invalid = false,
    this.ariaLabelledBy,
  });

  final List<AppRadioOption> options;
  final String? value;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final AppRadioGroupOrientation orientation;
  final bool disabled;
  final bool invalid;
  final String? ariaLabelledBy;

  @override
  State<AppRadioGroup> createState() => _AppRadioGroupState();
}

class _AppRadioGroupState extends State<AppRadioGroup> {
  String? _internalValue;
  late List<FocusNode> _focusNodes = _createFocusNodes();

  bool get _isControlled => widget.value != null;

  String? get _effectiveValue => widget.value ?? _internalValue;

  List<FocusNode> _createFocusNodes() => List.generate(widget.options.length, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _internalValue = widget.initialValue;
  }

  @override
  void didUpdateWidget(covariant AppRadioGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _focusNodes = _createFocusNodes();
    }
    if (!_isControlled && widget.initialValue != oldWidget.initialValue) {
      _internalValue = widget.initialValue;
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _select(String value) {
    if (widget.disabled || widget.options.any((opt) => opt.value == value && opt.disabled)) {
      return;
    }
    if (_isControlled && widget.onChanged == null) return;

    if (!_isControlled) {
      setState(() => _internalValue = value);
    }
    widget.onChanged?.call(value);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.disabled) return KeyEventResult.ignored;

    final currentIndex = widget.options.indexWhere((opt) => opt.value == _effectiveValue);
    final enabledIndices = [
      for (var i = 0; i < widget.options.length; i++)
        if (!widget.options[i].disabled && !widget.disabled) i,
    ];
    if (enabledIndices.isEmpty) return KeyEventResult.ignored;

    final currentPos = enabledIndices.indexOf(currentIndex);
    final startPos = currentPos >= 0 ? currentPos : 0;

    final bool forward;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.arrowDown) {
      forward = true;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.arrowUp) {
      forward = false;
    } else {
      return KeyEventResult.ignored;
    }

    final nextPos = forward
        ? (startPos + 1) % enabledIndices.length
        : (startPos - 1 + enabledIndices.length) % enabledIndices.length;
    final nextIndex = enabledIndices[nextPos];
    _select(widget.options[nextIndex].value);
    _focusNodes[nextIndex].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.orientation == AppRadioGroupOrientation.horizontal;

    final tiles = [
      for (var index = 0; index < widget.options.length; index++)
        _AppRadioOptionTile(
          option: widget.options[index],
          selected: widget.options[index].value == _effectiveValue,
          groupDisabled: widget.disabled,
          invalid: widget.invalid,
          focusNode: _focusNodes[index],
          onSelected: () => _select(widget.options[index].value),
        ),
    ];

    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      label: widget.ariaLabelledBy,
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: isHorizontal
            ? Wrap(
                spacing: AppSpacing.space3,
                runSpacing: AppSpacing.space3,
                children: tiles,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < tiles.length; index++) ...[
                    if (index > 0) const SizedBox(height: AppSpacing.space3),
                    tiles[index],
                  ],
                ],
              ),
      ),
    );
  }
}

class _AppRadioOptionTile extends StatefulWidget {
  const _AppRadioOptionTile({
    required this.option,
    required this.selected,
    required this.groupDisabled,
    required this.invalid,
    required this.focusNode,
    required this.onSelected,
  });

  final AppRadioOption option;
  final bool selected;
  final bool groupDisabled;
  final bool invalid;
  final FocusNode focusNode;
  final VoidCallback onSelected;

  @override
  State<_AppRadioOptionTile> createState() => _AppRadioOptionTileState();
}

class _AppRadioOptionTileState extends State<_AppRadioOptionTile> {
  static const _outerSize = 20.0;
  static const _innerSize = 10.0;

  var _focused = false;

  bool get _disabled => widget.groupDisabled || widget.option.disabled;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _AppRadioOptionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      widget.focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final focusRing = widget.invalid
        ? appInputInvalidFocusRingColor(colors)
        : appInputFocusRingColor(context);

    return Opacity(
      opacity: _disabled ? 0.5 : 1,
      child: Semantics(
        checked: widget.selected,
        enabled: !_disabled,
        inMutuallyExclusiveGroup: true,
        child: GestureDetector(
          onTap: _disabled ? null : widget.onSelected,
          behavior: HitTestBehavior.translucent,
          child: MouseRegion(
            cursor: _disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Focus(
                  focusNode: widget.focusNode,
                  canRequestFocus: !_disabled,
                  skipTraversal: !widget.selected,
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent || _disabled) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.space || event.logicalKey == LogicalKeyboardKey.enter) {
                      widget.onSelected();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    curve: AppMotion.standardCurve,
                    width: _outerSize,
                    height: _outerSize,
                    decoration: BoxDecoration(
                      color: colors.surfaceDefault,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.invalid
                            ? colors.statusDangerBorder
                            : (widget.selected ? colors.actionPrimary : colors.borderDefault),
                      ),
                      boxShadow: _focused
                          ? [BoxShadow(color: focusRing, blurRadius: 0, spreadRadius: 2)]
                          : null,
                    ),
                    child: Center(
                      child: AnimatedContainer(
                        duration: AppMotion.fast,
                        curve: AppMotion.standardCurve,
                        width: widget.selected ? _innerSize : 0,
                        height: widget.selected ? _innerSize : 0,
                        decoration: BoxDecoration(
                          color: colors.actionPrimary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.space2),
                Text(
                  widget.option.label,
                  style: AppTypography.body(context).copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
