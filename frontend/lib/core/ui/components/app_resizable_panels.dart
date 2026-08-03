import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// Two-pane layout with a draggable vertical divider (web `ResizablePanels`).
///
/// Keyboard: ArrowLeft/ArrowRight adjust the start pane by ±2% (mirrored in RTL).
/// Drag: pointer position is mirrored in RTL (`width - x`).
class AppResizablePanels extends StatefulWidget {
  const AppResizablePanels({
    required this.start,
    required this.end,
    this.defaultStartPercent = 35,
    this.minStartPercent = 20,
    this.maxStartPercent = 60,
    super.key,
  });

  final Widget start;
  final Widget end;
  final double defaultStartPercent;
  final double minStartPercent;
  final double maxStartPercent;

  static const _panelHeight = 256.0;
  static const _dividerWidth = 4.0;

  @override
  State<AppResizablePanels> createState() => _AppResizablePanelsState();
}

class _AppResizablePanelsState extends State<AppResizablePanels> {
  final _containerKey = GlobalKey();
  final _focusNode = FocusNode();

  late double _startPercent;
  var _dragging = false;
  var _dividerHovered = false;

  @override
  void initState() {
    super.initState();
    _startPercent = widget.defaultStartPercent;
    _focusNode
      ..addListener(_handleFocusChange)
      ..onKeyEvent = _handleKeyEvent;
  }

  @override
  void didUpdateWidget(covariant AppResizablePanels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.defaultStartPercent != widget.defaultStartPercent &&
        _startPercent == oldWidget.defaultStartPercent) {
      _startPercent = widget.defaultStartPercent;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..onKeyEvent = null
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() => setState(() {});

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;

  double _clampPercent(double value) =>
      value.clamp(widget.minStartPercent, widget.maxStartPercent);

  void _setStartPercent(double value) {
    final next = _clampPercent(value);
    if (next == _startPercent) return;
    setState(() => _startPercent = next);
  }

  void _adjustStartPercent(double delta) {
    _setStartPercent(_startPercent + delta);
  }

  void _updateFromGlobalPosition(Offset globalPosition) {
    final box = _containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(globalPosition);
    final width = box.size.width;
    if (width <= 0) return;

    final x = _isRtl ? width - local.dx : local.dx;
    _setStartPercent(x / width * 100);
  }

  void _handleDividerPointerDown(PointerDownEvent event) {
    _focusNode.requestFocus();
    setState(() => _dragging = true);
    _updateFromGlobalPosition(event.position);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_dragging) return;
    _updateFromGlobalPosition(event.position);
  }

  void _handlePointerUp(PointerEvent event) {
    if (!_dragging) return;
    setState(() => _dragging = false);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _adjustStartPercent(_isRtl ? 2 : -2);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _adjustStartPercent(_isRtl ? -2 : 2);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Color _dividerColor(AppSemanticColors colors) {
    if (_dividerHovered || _focusNode.hasFocus) {
      return colors.actionPrimary;
    }
    return colors.borderDefault;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final focusRing = appInputFocusRingColor(context);
    final rounded = BorderRadius.circular(AppRadius.lg);

    return Listener(
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerUp,
      child: DecoratedBox(
        key: _containerKey,
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderDefault),
          borderRadius: rounded,
        ),
        child: ClipRRect(
          borderRadius: rounded,
          child: SizedBox(
            height: AppResizablePanels._panelHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final startWidth = totalWidth * _startPercent / 100;

                return Row(
                  children: [
                    SizedBox(
                      width: startWidth,
                      child: SingleChildScrollView(
                        child: widget.start,
                      ),
                    ),
                    Semantics(
                      container: true,
                      label: 'Resize panels',
                      value: '${_startPercent.round()}',
                      increasedValue: '${_clampPercent(_startPercent + 2).round()}',
                      decreasedValue: '${_clampPercent(_startPercent - 2).round()}',
                      onIncrease: () => _adjustStartPercent(_isRtl ? -2 : 2),
                      onDecrease: () => _adjustStartPercent(_isRtl ? 2 : -2),
                      child: Focus(
                        focusNode: _focusNode,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          onEnter: (_) => setState(() => _dividerHovered = true),
                          onExit: (_) => setState(() => _dividerHovered = false),
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _handleDividerPointerDown,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: AppResizablePanels._dividerWidth,
                              decoration: BoxDecoration(
                                color: _dividerColor(colors),
                                boxShadow: _focusNode.hasFocus
                                    ? [
                                        BoxShadow(
                                          color: focusRing,
                                          blurRadius: 0,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: widget.end,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
