import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// A single option within an [AppRadioGroup].
class AppRadioOption<T> {
  const AppRadioOption({
    required this.value,
    required this.label,
    this.disabled = false,
  });

  final T value;
  final String label;
  final bool disabled;
}

/// Orientation for laying out radio options.
enum AppRadioGroupOrientation {
  vertical,
  horizontal,
}

/// Generic single-selection radio group with roving keyboard navigation.
class AppRadioGroup<T> extends StatefulWidget {
  const AppRadioGroup({
    required this.options,
    required this.value,
    required this.onChanged,
    this.orientation = AppRadioGroupOrientation.vertical,
    this.disabled = false,
    this.invalid = false,
    this.semanticLabel,
    super.key,
  });

  final List<AppRadioOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final AppRadioGroupOrientation orientation;
  final bool disabled;
  final bool invalid;
  final String? semanticLabel;

  @override
  State<AppRadioGroup<T>> createState() => _AppRadioGroupState<T>();
}

class _AppRadioGroupState<T> extends State<AppRadioGroup<T>> {
  final List<FocusNode> _focusNodes = [];
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncFocusNodes();
    _focusedIndex = _selectedIndex();
  }

  @override
  void didUpdateWidget(covariant AppRadioGroup<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.options.length != oldWidget.options.length) {
      _disposeFocusNodes();
      _syncFocusNodes();
    }
  }

  @override
  void dispose() {
    _disposeFocusNodes();
    super.dispose();
  }

  void _syncFocusNodes() {
    while (_focusNodes.length < widget.options.length) {
      _focusNodes.add(FocusNode());
    }
    while (_focusNodes.length > widget.options.length) {
      _focusNodes.removeLast().dispose();
    }
  }

  void _disposeFocusNodes() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
  }

  int _selectedIndex() {
    for (var i = 0; i < widget.options.length; i++) {
      if (widget.options[i].value == widget.value) return i;
    }
    return 0;
  }

  bool _isOptionDisabled(AppRadioOption<T> option) =>
      widget.disabled || option.disabled;

  void _select(int index) {
    final option = widget.options[index];
    if (_isOptionDisabled(option)) return;
    widget.onChanged(option.value);
    setState(() => _focusedIndex = index);
  }

  void _moveFocus(int delta) {
    if (widget.options.isEmpty) return;
    var next = _focusedIndex;
    for (var i = 0; i < widget.options.length; i++) {
      next = (next + delta + widget.options.length) % widget.options.length;
      if (!_isOptionDisabled(widget.options[next])) {
        setState(() => _focusedIndex = next);
        _focusNodes[next].requestFocus();
        return;
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isHorizontal =
        widget.orientation == AppRadioGroupOrientation.horizontal;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    LogicalKeyboardKey? forward;
    LogicalKeyboardKey? backward;
    if (isHorizontal) {
      forward = isRtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;
      backward = isRtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;
    } else {
      forward = LogicalKeyboardKey.arrowDown;
      backward = LogicalKeyboardKey.arrowUp;
    }

    if (event.logicalKey == forward) {
      _moveFocus(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == backward) {
      _moveFocus(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _select(_focusedIndex);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isVertical =
        widget.orientation == AppRadioGroupOrientation.vertical;

    return Semantics(
      label: widget.semanticLabel,
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: Wrap(
          direction: isVertical ? Axis.vertical : Axis.horizontal,
          spacing: isVertical ? 0 : AppSpacing.s3,
          runSpacing: AppSpacing.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < widget.options.length; i++)
              _AppRadioTile<T>(
                option: widget.options[i],
                selected: widget.options[i].value == widget.value,
                disabled: _isOptionDisabled(widget.options[i]),
                invalid: widget.invalid,
                focusNode: _focusNodes[i],
                onSelected: () => _select(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppRadioTile<T> extends StatelessWidget {
  const _AppRadioTile({
    required this.option,
    required this.selected,
    required this.disabled,
    required this.invalid,
    required this.focusNode,
    required this.onSelected,
  });

  final AppRadioOption<T> option;
  final bool selected;
  final bool disabled;
  final bool invalid;
  final FocusNode focusNode;
  final VoidCallback onSelected;

  static const double _outerSize = AppSpacing.s5;
  static const double _dotSize = AppSpacing.s2 + AppSpacing.s0_5;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final duration = AppMotion.reduced(context)
        ? AppDurations.instant
        : AppDurations.fast;

    return AppPressable.builder(
      onTap: disabled ? null : onSelected,
      enabled: !disabled,
      focusNode: focusNode,
      borderRadius: AppRadii.fullAll,
      builder: (context, states, _) {
        final borderColor = invalid
            ? colors.statusDangerBorder
            : selected
            ? colors.actionPrimary
            : colors.borderDefault;

        return Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: duration,
                curve: AppEasings.standard,
                width: _outerSize,
                height: _outerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceDefault,
                  border: Border.all(color: borderColor),
                ),
                child: Center(
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: duration,
                    curve: AppEasings.out,
                    child: Container(
                      width: _dotSize,
                      height: _dotSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.actionPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              Text(
                option.label,
                style: typography.body.copyWith(
                  color: disabled
                      ? colors.textDisabled
                      : colors.textPrimary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
