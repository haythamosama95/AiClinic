import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Layout axis for [AppResizablePanels].
enum AppResizeAxis {
  /// Panels arranged side by side with a vertical divider.
  horizontal,

  /// Panels stacked with a horizontal divider.
  vertical,
}

/// One pane inside [AppResizablePanels].
class AppResizablePanel {
  /// Creates a resizable panel definition.
  const AppResizablePanel({
    required this.child,
    this.initialFraction,
    this.minFraction = 0.2,
    this.maxFraction = 1,
  });

  /// Panel content. May itself be an [AppResizablePanels] for nesting.
  final Widget child;

  /// Initial size as a fraction of the container (0–1). Normalized with
  /// sibling [initialFraction] values when more than one panel is present.
  final double? initialFraction;

  /// Minimum allowed fraction for this panel.
  final double minFraction;

  /// Maximum allowed fraction for this panel.
  final double maxFraction;
}

/// Custom split layout with draggable, keyboard-adjustable dividers.
///
/// Supports two or more panels, RTL-aware horizontal drag math, optional
/// fraction persistence via [onChanged], and nesting by placing another
/// [AppResizablePanels] inside a panel [child].
class AppResizablePanels extends StatefulWidget {
  /// Creates a resizable panel group.
  const AppResizablePanels({
    required this.panels,
    super.key,
    this.axis = AppResizeAxis.horizontal,
    this.initialFractions,
    this.onChanged,
    this.storageKey,
  }) : assert(panels.length >= 2, 'At least two panels are required');

  /// Axis along which panels are arranged.
  final AppResizeAxis axis;

  /// Panel definitions (minimum two).
  final List<AppResizablePanel> panels;

  /// Restored fractions from persistence (length must match [panels]).
  final List<double>? initialFractions;

  /// Called whenever divider positions change. Parents persist using
  /// [storageKey] or their own key strategy.
  final ValueChanged<List<double>>? onChanged;

  /// Optional key hint for parent persistence; not read by this widget.
  final String? storageKey;

  @override
  State<AppResizablePanels> createState() => _AppResizablePanelsState();
}

class _AppResizablePanelsState extends State<AppResizablePanels> {
  static const double _keyboardStep = 0.02;
  static const int _flexScale = 10000;

  final GlobalKey _containerKey = GlobalKey();
  late List<double> _fractions;
  int? _activeDivider;

  @override
  void initState() {
    super.initState();
    _fractions = _resolveInitialFractions();
  }

  @override
  void didUpdateWidget(covariant AppResizablePanels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panels.length != widget.panels.length ||
        oldWidget.initialFractions != widget.initialFractions) {
      _fractions = _resolveInitialFractions();
    }
  }

  List<double> _resolveInitialFractions() {
    final restored = widget.initialFractions;
    if (restored != null && restored.length == widget.panels.length) {
      return _normalizeFractions(restored);
    }

    final specified = widget.panels
        .map((panel) => panel.initialFraction)
        .whereType<double>()
        .toList();
    if (specified.length == widget.panels.length) {
      final sum = specified.fold<double>(0, (total, value) => total + value);
      if (sum > 0) {
        return specified.map((value) => value / sum).toList();
      }
    }

    final equal = 1 / widget.panels.length;
    return List<double>.filled(widget.panels.length, equal);
  }

  List<double> _normalizeFractions(List<double> values) {
    final clamped = <double>[];
    for (var i = 0; i < values.length; i++) {
      final panel = widget.panels[i];
      clamped.add(
        values[i].clamp(panel.minFraction, panel.maxFraction).toDouble(),
      );
    }
    final sum = clamped.fold<double>(0, (total, value) => total + value);
    if (sum <= 0) {
      final equal = 1 / widget.panels.length;
      return List<double>.filled(widget.panels.length, equal);
    }
    return clamped.map((value) => value / sum).toList();
  }

  double _boundaryForDivider(int dividerIndex) {
    var total = 0.0;
    for (var i = 0; i <= dividerIndex; i++) {
      total += _fractions[i];
    }
    return total;
  }

  void _setBoundary(int dividerIndex, double boundary) {
    final oldBoundary = _boundaryForDivider(dividerIndex);
    var delta = boundary - oldBoundary;

    var leading = _fractions[dividerIndex] + delta;
    var trailing = _fractions[dividerIndex + 1] - delta;

    final leadingPanel = widget.panels[dividerIndex];
    final trailingPanel = widget.panels[dividerIndex + 1];

    if (leading < leadingPanel.minFraction) {
      final correction = leadingPanel.minFraction - leading;
      leading = leadingPanel.minFraction;
      trailing -= correction;
    } else if (leading > leadingPanel.maxFraction) {
      final correction = leadingPanel.maxFraction - leading;
      leading = leadingPanel.maxFraction;
      trailing -= correction;
    }

    if (trailing < trailingPanel.minFraction) {
      final correction = trailingPanel.minFraction - trailing;
      trailing = trailingPanel.minFraction;
      leading -= correction;
    } else if (trailing > trailingPanel.maxFraction) {
      final correction = trailingPanel.maxFraction - trailing;
      trailing = trailingPanel.maxFraction;
      leading -= correction;
    }

    leading = leading.clamp(leadingPanel.minFraction, leadingPanel.maxFraction);
    trailing = trailing.clamp(
      trailingPanel.minFraction,
      trailingPanel.maxFraction,
    );

    if (leading == _fractions[dividerIndex] &&
        trailing == _fractions[dividerIndex + 1]) {
      return;
    }

    setState(() {
      _fractions[dividerIndex] = leading;
      _fractions[dividerIndex + 1] = trailing;
    });
    widget.onChanged?.call(List<double>.from(_fractions));
  }

  double _pointerToFraction(Offset globalPosition) {
    final box = _containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return 0;

    final local = box.globalToLocal(globalPosition);
    final isHorizontal = widget.axis == AppResizeAxis.horizontal;

    if (isHorizontal) {
      final width = box.size.width;
      if (width <= 0) return 0;
      final isRtl = Directionality.of(context) == TextDirection.rtl;
      final x = isRtl ? width - local.dx : local.dx;
      return (x / width).clamp(0.0, 1.0);
    }

    final height = box.size.height;
    if (height <= 0) return 0;
    return (local.dy / height).clamp(0.0, 1.0);
  }

  void _handleDividerDrag(int dividerIndex, Offset globalPosition) {
    _setBoundary(dividerIndex, _pointerToFraction(globalPosition));
  }

  void _handleDividerKey(int dividerIndex, int direction) {
    final isHorizontal = widget.axis == AppResizeAxis.horizontal;
    if (isHorizontal) {
      final isRtl = Directionality.of(context) == TextDirection.rtl;
      if (isRtl) direction = -direction;
    }
    _setBoundary(
      dividerIndex,
      _boundaryForDivider(dividerIndex) + direction * _keyboardStep,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.axis == AppResizeAxis.horizontal;

    return LayoutBuilder(
      key: _containerKey,
      builder: (context, constraints) {
        final children = <Widget>[];
        for (var i = 0; i < widget.panels.length; i++) {
          children.add(
            Expanded(
              flex: (_fractions[i] * _flexScale).round().clamp(1, _flexScale),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: isHorizontal ? 0 : constraints.maxWidth,
                  maxWidth: isHorizontal ? double.infinity : constraints.maxWidth,
                  minHeight: isHorizontal ? constraints.maxHeight : 0,
                  maxHeight: isHorizontal ? constraints.maxHeight : double.infinity,
                  child: widget.panels[i].child,
                ),
              ),
            ),
          );
          if (i < widget.panels.length - 1) {
            children.add(
              _ResizeDivider(
                axis: widget.axis,
                valuePercent: (_boundaryForDivider(i) * 100).round(),
                minPercent: (widget.panels[i].minFraction * 100).round(),
                maxPercent: (widget.panels[i].maxFraction * 100).round(),
                onDragStart: () => _activeDivider = i,
                onDragUpdate: (position) =>
                    _handleDividerDrag(i, position),
                onDragEnd: () => _activeDivider = null,
                onKeyDelta: (direction) => _handleDividerKey(i, direction),
              ),
            );
          }
        }

        return Listener(
          onPointerMove: _activeDivider != null
              ? (event) => _handleDividerDrag(_activeDivider!, event.position)
              : null,
          onPointerUp: _activeDivider != null
              ? (_) => _activeDivider = null
              : null,
          onPointerCancel: _activeDivider != null
              ? (_) => _activeDivider = null
              : null,
          child: isHorizontal
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
        );
      },
    );
  }
}

class _ResizeDivider extends StatefulWidget {
  const _ResizeDivider({
    required this.axis,
    required this.valuePercent,
    required this.minPercent,
    required this.maxPercent,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onKeyDelta,
  });

  final AppResizeAxis axis;
  final int valuePercent;
  final int minPercent;
  final int maxPercent;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final ValueChanged<int> onKeyDelta;

  @override
  State<_ResizeDivider> createState() => _ResizeDividerState();
}

class _ResizeDividerState extends State<_ResizeDivider> {
  late final FocusNode _focusNode;
  bool _hovered = false;
  bool _focused = false;

  bool get _isHorizontal => widget.axis == AppResizeAxis.horizontal;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (_focused != focused) {
      setState(() => _focused = focused);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isHorizontal = _isHorizontal;
    int? direction;

    if (isHorizontal) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        direction = -1;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        direction = 1;
      }
    } else {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        direction = -1;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        direction = 1;
      }
    }

    if (direction == null) return KeyEventResult.ignored;
    widget.onKeyDelta(direction);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isHorizontal = _isHorizontal;

    Color dividerColor = colors.borderDefault;
    if (_focused) {
      dividerColor = colors.borderFocus;
    } else if (_hovered) {
      dividerColor = colors.borderStrong;
    }

    final cursor = isHorizontal
        ? SystemMouseCursors.resizeColumn
        : SystemMouseCursors.resizeRow;

    Widget divider = AnimatedContainer(
      duration: AppDurations.fast,
      curve: AppEasings.standard,
      width: isHorizontal ? AppSpacing.s1 : double.infinity,
      height: isHorizontal ? double.infinity : AppSpacing.s1,
      color: dividerColor,
    );

    divider = AppFocusRing(
      visible: _focused,
      borderRadius: BorderRadius.zero,
      child: divider,
    );

    divider = MouseRegion(
      cursor: cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: divider,
    );

    divider = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        widget.onDragStart();
        widget.onDragUpdate(event.position);
        _focusNode.requestFocus();
      },
      child: divider,
    );

    return Semantics(
      container: true,
      slider: true,
      label: 'Resize panels',
      value: '${widget.valuePercent}',
      increasedValue: '${(widget.valuePercent + 2).clamp(widget.minPercent, widget.maxPercent)}',
      decreasedValue: '${(widget.valuePercent - 2).clamp(widget.minPercent, widget.maxPercent)}',
      onIncrease: () => widget.onKeyDelta(1),
      onDecrease: () => widget.onKeyDelta(-1),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        child: divider,
      ),
    );
  }
}
