import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Size scale for segmented controls.
enum AppSegmentedControlSize {
  sm,
  md,
}

/// One mutually exclusive option inside [AppSegmentedControl].
class AppSegmentedOption<T> {
  const AppSegmentedOption({
    required this.value,
    required this.label,
    this.icon,
    this.disabled = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool disabled;
}

/// Mutually exclusive choice among 2–5 short labeled options.
class AppSegmentedControl<T> extends StatefulWidget {
  const AppSegmentedControl({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.size = AppSegmentedControlSize.md,
    super.key,
  }) : assert(options.length >= 2 && options.length <= 5);

  final List<AppSegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String semanticLabel;
  final AppSegmentedControlSize size;

  @override
  State<AppSegmentedControl<T>> createState() => _AppSegmentedControlState<T>();
}

class _AppSegmentedControlState<T> extends State<AppSegmentedControl<T>> {
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _focusNodes = List.generate(widget.options.length, (_) => FocusNode());
  }

  @override
  void didUpdateWidget(covariant AppSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _focusNodes = List.generate(widget.options.length, (_) => FocusNode());
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  double get _height => switch (widget.size) {
    AppSegmentedControlSize.sm => AppSpacing.s8 - AppSpacing.s1,
    AppSegmentedControlSize.md => AppSpacing.s8 + AppSpacing.s1,
  };

  TextStyle _textStyle(BuildContext context) {
    final typography = context.typography;
    return widget.size == AppSegmentedControlSize.sm
        ? typography.bodySm
        : typography.bodyStrong;
  }

  List<int> get _enabledIndices => [
    for (var i = 0; i < widget.options.length; i++)
      if (!widget.options[i].disabled) i,
  ];

  void _focusIndex(int index) {
    if (index < 0 || index >= _focusNodes.length) return;
    _focusNodes[index].requestFocus();
  }

  void _selectIndex(int index) {
    final option = widget.options[index];
    if (option.disabled) return;
    widget.onChanged(option.value);
    _focusIndex(index);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final enabled = _enabledIndices;
    if (enabled.isEmpty) return KeyEventResult.ignored;

    final currentIndex = widget.options.indexWhere((o) => o.value == widget.value);
    final currentEnabledPos = enabled.indexOf(currentIndex);
    if (currentEnabledPos < 0) return KeyEventResult.ignored;

    final isRtl = Directionality.of(context) == TextDirection.rtl;

    int? nextEnabledPos;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      nextEnabledPos = isRtl
          ? (currentEnabledPos - 1 + enabled.length) % enabled.length
          : (currentEnabledPos + 1) % enabled.length;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      nextEnabledPos = isRtl
          ? (currentEnabledPos + 1) % enabled.length
          : (currentEnabledPos - 1 + enabled.length) % enabled.length;
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      nextEnabledPos = 0;
    } else if (event.logicalKey == LogicalKeyboardKey.end) {
      nextEnabledPos = enabled.length - 1;
    }

    if (nextEnabledPos == null) return KeyEventResult.ignored;

    final nextIndex = enabled[nextEnabledPos];
    _selectIndex(nextIndex);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderRadius = AppRadii.mdAll;

    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Semantics(
          container: true,
          label: widget.semanticLabel,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceDefault,
              borderRadius: borderRadius,
              border: Border.all(color: colors.borderDefault),
            ),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < widget.options.length; index++)
                    _Segment(
                      option: widget.options[index],
                      selected: widget.options[index].value == widget.value,
                      isFirst: index == 0,
                      height: _height,
                      textStyle: _textStyle(context),
                      focusNode: _focusNodes[index],
                      skipTraversal:
                          widget.options[index].value != widget.value,
                      onPressed: () => _selectIndex(index),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.isFirst,
    required this.height,
    required this.textStyle,
    required this.focusNode,
    required this.skipTraversal,
    required this.onPressed,
  });

  final AppSegmentedOption<dynamic> option;
  final bool selected;
  final bool isFirst;
  final double height;
  final TextStyle textStyle;
  final FocusNode focusNode;
  final bool skipTraversal;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Focus(
      skipTraversal: skipTraversal,
      child: AppPressable.builder(
        enabled: !option.disabled,
        onTap: onPressed,
        focusNode: focusNode,
        borderRadius: BorderRadius.zero,
        builder: (context, states, _) {
          final background = option.disabled
              ? Colors.transparent
              : selected
              ? colors.surfaceSelected
              : states.contains(WidgetState.hovered)
              ? colors.surfaceHover
              : Colors.transparent;
          final foreground = option.disabled
              ? colors.textDisabled
              : selected
              ? colors.textPrimary
              : states.contains(WidgetState.hovered)
              ? colors.textPrimary
              : colors.textSecondary;

          return AnimatedContainer(
            duration: AppDurations.instant,
            curve: AppEasings.standard,
            height: height,
            constraints: const BoxConstraints(minWidth: AppSpacing.s12),
            padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s3),
            decoration: BoxDecoration(
              color: background,
              border: isFirst
                  ? null
                  : BorderDirectional(
                      start: BorderSide(color: colors.borderDefault),
                    ),
            ),
            child: Semantics(
              inMutuallyExclusiveGroup: true,
              checked: selected,
              button: true,
              enabled: !option.disabled,
              label: option.label,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (option.icon != null) ...[
                    AppIcon(
                      icon: option.icon!,
                      size: AppIconSize.sm,
                      color: foreground,
                    ),
                    const SizedBox(width: AppSpacing.s1 + AppSpacing.s0_5),
                  ],
                  Text(
                    option.label,
                    style: textStyle.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
