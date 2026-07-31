import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Size variants for [AppSegmentedControl] (web `sm` | `md`).
enum AppSegmentedControlSize { sm, md }

/// A single option in [AppSegmentedControl].
class SegmentedOption<T extends String> {
  const SegmentedOption({required this.value, required this.label, this.disabled = false});

  final T value;
  final Widget label;
  final bool disabled;
}

/// Application-owned segmented control (`04-components` A4).
///
/// Mutually exclusive choice among 2–5 options with `radiogroup` semantics and
/// roving arrow-key navigation matching the web `SegmentedControl`.
class AppSegmentedControl<T extends String> extends StatefulWidget {
  const AppSegmentedControl({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.ariaLabel,
    this.size = AppSegmentedControlSize.md,
    super.key,
  });

  final List<SegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String ariaLabel;
  final AppSegmentedControlSize size;

  @override
  State<AppSegmentedControl<T>> createState() => _AppSegmentedControlState<T>();
}

class _AppSegmentedControlState<T extends String> extends State<AppSegmentedControl<T>> {
  late List<FocusNode> _focusNodes = _createFocusNodes();

  List<FocusNode> _createFocusNodes() => List.generate(widget.options.length, (_) => FocusNode());

  @override
  void didUpdateWidget(covariant AppSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _focusNodes = _createFocusNodes();
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  List<int> get _enabledIndices {
    return [
      for (var i = 0; i < widget.options.length; i++)
        if (!widget.options[i].disabled) i,
    ];
  }

  void _focusItem(int index) {
    _focusNodes[index].requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final currentIndex = widget.options.indexWhere((option) => option.value == widget.value);
    final enabledIndices = _enabledIndices;
    final currentEnabledPos = enabledIndices.indexOf(currentIndex);
    if (currentEnabledPos < 0) return KeyEventResult.ignored;

    final int nextEnabledPos;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.arrowDown) {
      nextEnabledPos = (currentEnabledPos + 1) % enabledIndices.length;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.arrowUp) {
      nextEnabledPos = (currentEnabledPos - 1 + enabledIndices.length) % enabledIndices.length;
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      nextEnabledPos = 0;
    } else if (event.logicalKey == LogicalKeyboardKey.end) {
      nextEnabledPos = enabledIndices.length - 1;
    } else {
      return KeyEventResult.ignored;
    }

    final nextIndex = enabledIndices[nextEnabledPos];
    widget.onChanged(widget.options[nextIndex].value);
    _focusItem(nextIndex);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final height = switch (widget.size) {
      AppSegmentedControlSize.sm => 28.0,
      AppSegmentedControlSize.md => 36.0,
    };
    final textStyle = switch (widget.size) {
      AppSegmentedControlSize.sm => AppTypography.bodySm(context),
      AppSegmentedControlSize.md => AppTypography.bodyStrong(context),
    };

    final borderRadius = BorderRadius.circular(AppRadius.md);
    final groupBorder = Border.all(color: colors.borderDefault);

    return Semantics(
      container: true,
      label: widget.ariaLabel,
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: colors.surfaceDefault, borderRadius: borderRadius),
              child: ClipRRect(
                borderRadius: borderRadius,
                child: IntrinsicHeight(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < widget.options.length; index++)
                        _SegmentedControlItem<T>(
                          option: widget.options[index],
                          selected: widget.options[index].value == widget.value,
                          isFirst: index == 0,
                          isLast: index == widget.options.length - 1,
                          height: height,
                          textStyle: textStyle,
                          focusNode: _focusNodes[index],
                          onSelected: () => widget.onChanged(widget.options[index].value),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(border: groupBorder, borderRadius: borderRadius),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedControlItem<T extends String> extends StatefulWidget {
  const _SegmentedControlItem({
    required this.option,
    required this.selected,
    required this.isFirst,
    required this.isLast,
    required this.height,
    required this.textStyle,
    required this.focusNode,
    required this.onSelected,
  });

  final SegmentedOption<T> option;
  final bool selected;
  final bool isFirst;
  final bool isLast;
  final double height;
  final TextStyle textStyle;
  final FocusNode focusNode;
  final VoidCallback onSelected;

  @override
  State<_SegmentedControlItem<T>> createState() => _SegmentedControlItemState<T>();
}

class _SegmentedControlItemState<T extends String> extends State<_SegmentedControlItem<T>> {
  bool _hovered = false;

  Color _textColor(AppSemanticColors colors) {
    if (widget.option.disabled) {
      return Theme.of(context).brightness == Brightness.dark
          ? AppColorPrimitives.textDisabledDark
          : AppColorPrimitives.neutral400;
    }
    if (widget.selected || _hovered) {
      return colors.textPrimary;
    }
    return colors.textSecondary;
  }

  Color _backgroundColor(AppSemanticColors colors) {
    if (widget.selected) {
      return colors.surfaceSelected;
    }
    if (_hovered && !widget.option.disabled) {
      return colors.surfaceHover;
    }
    return Colors.transparent;
  }

  BorderRadiusGeometry _borderRadius() {
    if (widget.isFirst && widget.isLast) {
      return BorderRadius.circular(AppRadius.md);
    }
    if (widget.isFirst) {
      return const BorderRadiusDirectional.horizontal(start: Radius.circular(AppRadius.md));
    }
    if (widget.isLast) {
      return const BorderRadiusDirectional.horizontal(end: Radius.circular(AppRadius.md));
    }
    return BorderRadius.zero;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      enabled: !widget.option.disabled,
      selected: widget.selected,
      inMutuallyExclusiveGroup: true,
      child: Focus(
        focusNode: widget.focusNode,
        skipTraversal: !widget.selected,
        canRequestFocus: !widget.option.disabled,
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;

            return MouseRegion(
              onEnter: widget.option.disabled ? null : (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              cursor: widget.option.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.option.disabled ? null : widget.onSelected,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: BoxConstraints(minWidth: 48, minHeight: widget.height),
                  decoration: BoxDecoration(
                    color: _backgroundColor(colors),
                    borderRadius: _borderRadius(),
                    border: Border(left: widget.isFirst ? BorderSide.none : BorderSide(color: colors.borderDefault)),
                    boxShadow: focused
                        ? [BoxShadow(color: colors.actionPrimary.withValues(alpha: 0.35), spreadRadius: 1)]
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
                    child: Center(
                      child: DefaultTextStyle(
                        style: widget.textStyle.copyWith(color: _textColor(colors)),
                        child: IconTheme(
                          data: IconThemeData(color: _textColor(colors), size: 14),
                          child: widget.option.label,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
