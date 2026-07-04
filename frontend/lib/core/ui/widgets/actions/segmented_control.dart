import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

enum AppSegmentedControlSize { sm, md }

@immutable
class AppSegmentedOption<T> {
  const AppSegmentedOption({
    required this.value,
    required this.label,
    this.disabled = false,
  });

  final T value;
  final Widget label;
  final bool disabled;
}

/// Segmented single-choice control with animated sliding selection highlight.
class AppSegmentedControl<T> extends StatefulWidget {
  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.semanticLabel,
    this.size = AppSegmentedControlSize.md,
  });

  final List<AppSegmentedOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String semanticLabel;
  final AppSegmentedControlSize size;

  @override
  State<AppSegmentedControl<T>> createState() => _AppSegmentedControlState<T>();
}

class _AppSegmentedControlState<T> extends State<AppSegmentedControl<T>> {
  final GlobalKey _containerKey = GlobalKey();
  final List<GlobalKey> _segmentKeys = [];
  final List<FocusNode> _focusNodes = [];

  double _highlightStart = 0;
  double _highlightExtent = 0;
  bool _highlightReady = false;

  double get _height => widget.size == AppSegmentedControlSize.sm ? 28 : 36;

  TextStyle get _labelStyle => widget.size == AppSegmentedControlSize.sm
      ? context.typography.bodySm
      : context.typography.bodyStrong;

  @override
  void initState() {
    super.initState();
    _syncKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHighlight());
  }

  @override
  void didUpdateWidget(AppSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      _disposeFocusNodes();
      _syncKeys();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHighlight());
  }

  @override
  void dispose() {
    _disposeFocusNodes();
    super.dispose();
  }

  void _syncKeys() {
    _segmentKeys
      ..clear()
      ..addAll(List.generate(widget.options.length, (_) => GlobalKey()));
    _disposeFocusNodes();
    _focusNodes.addAll(
      List.generate(widget.options.length, (_) => FocusNode()),
    );
  }

  void _disposeFocusNodes() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
  }

  List<int> get _enabledIndices => [
    for (var i = 0; i < widget.options.length; i++)
      if (!widget.options[i].disabled) i,
  ];

  int get _selectedIndex =>
      widget.options.indexWhere((option) => option.value == widget.selected);

  void _updateHighlight() {
    if (!mounted) return;
    final selectedIndex = _selectedIndex;
    if (selectedIndex < 0 || selectedIndex >= _segmentKeys.length) return;

    final segmentBox =
        _segmentKeys[selectedIndex].currentContext?.findRenderObject()
            as RenderBox?;
    final containerBox =
        _containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (segmentBox == null ||
        containerBox == null ||
        !segmentBox.hasSize ||
        !containerBox.hasSize) {
      return;
    }

    final offset = segmentBox.localToGlobal(
      Offset.zero,
      ancestor: containerBox,
    );
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final nextStart = isRtl
        ? containerBox.size.width - offset.dx - segmentBox.size.width
        : offset.dx;

    setState(() {
      _highlightStart = nextStart;
      _highlightExtent = segmentBox.size.width;
      _highlightReady = true;
    });
  }

  void _focusSegment(int index) {
    if (index >= 0 && index < _focusNodes.length) {
      _focusNodes[index].requestFocus();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final enabled = _enabledIndices;
    if (enabled.isEmpty) return KeyEventResult.ignored;

    final currentIndex = _selectedIndex;
    final currentEnabledPos = enabled.indexOf(currentIndex);
    if (currentEnabledPos < 0) return KeyEventResult.ignored;

    int? nextEnabledPos;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      nextEnabledPos = (currentEnabledPos + 1) % enabled.length;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      nextEnabledPos =
          (currentEnabledPos - 1 + enabled.length) % enabled.length;
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      nextEnabledPos = 0;
    } else if (event.logicalKey == LogicalKeyboardKey.end) {
      nextEnabledPos = enabled.length - 1;
    } else {
      return KeyEventResult.ignored;
    }

    final nextIndex = enabled[nextEnabledPos];
    final nextValue = widget.options[nextIndex].value;
    widget.onChanged(nextValue);
    _focusSegment(nextIndex);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reducedMotion = AppMotion.isReducedMotion(context);
    final highlightDuration = reducedMotion
        ? Duration.zero
        : AppDurations.instant;

    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: DecoratedBox(
          key: _containerKey,
          decoration: BoxDecoration(
            color: colors.surfaceDefault,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: colors.borderDefault),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.mdAll,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  height: _height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (_highlightReady)
                        AnimatedPositioned(
                          duration: highlightDuration,
                          curve: AppCurves.standard,
                          left: Directionality.of(context) == TextDirection.rtl
                              ? null
                              : _highlightStart,
                          right: Directionality.of(context) == TextDirection.rtl
                              ? _highlightStart
                              : null,
                          top: 0,
                          bottom: 0,
                          width: _highlightExtent,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surfaceSelected,
                              borderRadius: AppRadius.mdAll,
                            ),
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < widget.options.length; i++)
                            _Segment<T>(
                              key: _segmentKeys[i],
                              option: widget.options[i],
                              selected:
                                  widget.options[i].value == widget.selected,
                              labelStyle: _labelStyle,
                              focusNode: _focusNodes[i],
                              showDivider: i > 0,
                              onSelected: () {
                                if (!widget.options[i].disabled) {
                                  widget.onChanged(widget.options[i].value);
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _updateHighlight(),
                                  );
                                }
                              },
                              onFocus: () =>
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _updateHighlight(),
                                  ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment<T> extends StatefulWidget {
  const _Segment({
    super.key,
    required this.option,
    required this.selected,
    required this.labelStyle,
    required this.focusNode,
    required this.showDivider,
    required this.onSelected,
    required this.onFocus,
  });

  final AppSegmentedOption<T> option;
  final bool selected;
  final TextStyle labelStyle;
  final FocusNode focusNode;
  final bool showDivider;
  final VoidCallback onSelected;
  final VoidCallback onFocus;

  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

class _SegmentState<T> extends State<_Segment<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disabled = widget.option.disabled;
    final selected = widget.selected;

    Color foreground;
    if (disabled) {
      foreground = colors.textDisabled;
    } else if (selected) {
      foreground = colors.textPrimary;
    } else if (_hovered) {
      foreground = colors.textPrimary;
    } else {
      foreground = colors.textSecondary;
    }

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (focused) widget.onFocus();
      },
      child: MouseRegion(
        onEnter: disabled ? null : (_) => setState(() => _hovered = true),
        onExit: disabled ? null : (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : widget.onSelected,
          child: Semantics(
            inMutuallyExclusiveGroup: true,
            checked: selected,
            button: true,
            enabled: !disabled,
            child: AnimatedContainer(
              duration: AppDurations.instant,
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
              alignment: Alignment.center,
              color: !selected && _hovered && !disabled
                  ? colors.surfaceHover
                  : Colors.transparent,
              foregroundDecoration: widget.showDivider
                  ? BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(color: colors.borderDefault),
                      ),
                    )
                  : null,
              child: DefaultTextStyle(
                style: widget.labelStyle.copyWith(color: foreground),
                child: widget.option.label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
