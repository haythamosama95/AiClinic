import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Scrollable region with token-styled scrollbars, keyboard navigation, and
/// optional edge-fade hints when content overflows.
class AppScrollArea extends StatefulWidget {
  /// Creates a scroll area around [child].
  const AppScrollArea({
    required this.child,
    super.key,
    this.axis = Axis.vertical,
    this.maxHeight,
    this.maxWidth,
    this.fadeEdges = true,
    this.controller,
  });

  /// Content placed inside the scroll viewport.
  final Widget child;

  /// Scroll direction. Defaults to vertical.
  final Axis axis;

  /// Maximum height of the viewport (vertical axis).
  final double? maxHeight;

  /// Maximum width of the viewport (horizontal axis).
  final double? maxWidth;

  /// Whether to fade content at overflow edges via [ShaderMask].
  final bool fadeEdges;

  /// Optional external scroll controller.
  final ScrollController? controller;

  @override
  State<AppScrollArea> createState() => _AppScrollAreaState();
}

class _AppScrollAreaState extends State<AppScrollArea> {
  static const double _keyboardScrollStep = AppSpacing.s10;

  late final ScrollController _controller;
  late final FocusNode _focusNode;
  bool _ownsController = false;
  bool _canScrollTowardStart = false;
  bool _canScrollTowardEnd = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = ScrollController();
      _ownsController = true;
    }
    _focusNode = FocusNode();
    _controller.addListener(_handleScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleScrollChanged());
  }

  @override
  void didUpdateWidget(covariant AppScrollArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_handleScrollChanged);
      if (_ownsController) {
        _controller.dispose();
      }
      if (widget.controller != null) {
        _controller = widget.controller!;
        _ownsController = false;
      } else {
        _controller = ScrollController();
        _ownsController = true;
      }
      _controller.addListener(_handleScrollChanged);
      _handleScrollChanged();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScrollChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _focusNode.dispose();
    super.dispose();
  }

  void _handleScrollChanged() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final towardStart = position.pixels > position.minScrollExtent + 0.5;
    final towardEnd = position.pixels < position.maxScrollExtent - 0.5;
    if (towardStart != _canScrollTowardStart ||
        towardEnd != _canScrollTowardEnd) {
      setState(() {
        _canScrollTowardStart = towardStart;
        _canScrollTowardEnd = towardEnd;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (_controller.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == _controller.offset) return;
    _controller.jumpTo(target);
  }

  Map<ShortcutActivator, Intent> get _shortcuts {
    if (widget.axis == Axis.vertical) {
      return const {
        SingleActivator(LogicalKeyboardKey.arrowUp): _ScrollAreaIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowDown): _ScrollAreaIntent(1),
        SingleActivator(LogicalKeyboardKey.pageUp): _ScrollAreaIntent(-1, large: true),
        SingleActivator(LogicalKeyboardKey.pageDown): _ScrollAreaIntent(1, large: true),
        SingleActivator(LogicalKeyboardKey.home): _ScrollAreaIntent(-2),
        SingleActivator(LogicalKeyboardKey.end): _ScrollAreaIntent(2),
      };
    }
    return const {
      SingleActivator(LogicalKeyboardKey.arrowLeft): _ScrollAreaIntent(-1),
      SingleActivator(LogicalKeyboardKey.arrowRight): _ScrollAreaIntent(1),
      SingleActivator(LogicalKeyboardKey.pageUp): _ScrollAreaIntent(-1, large: true),
      SingleActivator(LogicalKeyboardKey.pageDown): _ScrollAreaIntent(1, large: true),
      SingleActivator(LogicalKeyboardKey.home): _ScrollAreaIntent(-2),
      SingleActivator(LogicalKeyboardKey.end): _ScrollAreaIntent(2),
    };
  }

  void _handleScrollIntent(_ScrollAreaIntent intent) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final viewport = position.viewportDimension;

    switch (intent.mode) {
      case -2:
        _controller.jumpTo(position.minScrollExtent);
      case -1:
        _scrollBy(-(intent.large ? viewport : _keyboardScrollStep));
      case 1:
        _scrollBy(intent.large ? viewport : _keyboardScrollStep);
      case 2:
        _controller.jumpTo(position.maxScrollExtent);
    }
  }

  Widget _buildScrollView() {
    final scrollView = widget.axis == Axis.vertical
        ? SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.vertical,
            child: widget.child,
          )
        : SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: widget.child,
          );

    Widget content = scrollView;

    if (widget.fadeEdges) {
      content = _EdgeFadeMask(
        axis: widget.axis,
        canFadeTowardStart: _canScrollTowardStart,
        canFadeTowardEnd: _canScrollTowardEnd,
        surfaceColor: context.colors.surfaceDefault,
        child: scrollView,
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification ||
            notification is ScrollMetricsNotification) {
          _handleScrollChanged();
        }
        return false;
      },
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget child = LayoutBuilder(
      builder: (context, constraints) {
        Widget scrollable = _buildScrollView();

        scrollable = ScrollbarTheme(
          data: ScrollbarThemeData(
            thickness: WidgetStateProperty.all(AppSpacing.s1),
            radius: const Radius.circular(AppRadii.sm),
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.dragged) ||
                  states.contains(WidgetState.hovered)) {
                return colors.borderStrong;
              }
              return colors.borderDefault;
            }),
            crossAxisMargin: AppSpacing.s0_5,
            mainAxisMargin: AppSpacing.s1,
            minThumbLength: AppSpacing.s6,
          ),
          child: Scrollbar(
            controller: _controller,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == widget.axis,
            child: scrollable,
          ),
        );

        final maxHeight = widget.maxHeight;
        final maxWidth = widget.maxWidth;
        if (maxHeight != null || maxWidth != null) {
          scrollable = ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxHeight ?? double.infinity,
              maxWidth: maxWidth ?? double.infinity,
            ),
            child: scrollable,
          );
        }

        return scrollable;
      },
    );

    child = Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: {
          _ScrollAreaIntent: CallbackAction<_ScrollAreaIntent>(
            onInvoke: (intent) {
              _handleScrollIntent(intent);
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _focusNode,
          child: Semantics(
            container: true,
            label: 'Scrollable content',
            child: child,
          ),
        ),
      ),
    );

    return child;
  }
}

class _ScrollAreaIntent extends Intent {
  const _ScrollAreaIntent(this.mode, {this.large = false});

  /// `-2` home, `-1` toward start, `1` toward end, `2` end.
  final int mode;
  final bool large;
}

/// Applies start/end edge fades only when the scroll view can move in that
/// direction. Uses [ShaderMask] with a surface-colored fringe (web gradient
/// equivalent).
class _EdgeFadeMask extends StatelessWidget {
  const _EdgeFadeMask({
    required this.axis,
    required this.canFadeTowardStart,
    required this.canFadeTowardEnd,
    required this.surfaceColor,
    required this.child,
  });

  final Axis axis;
  final bool canFadeTowardStart;
  final bool canFadeTowardEnd;
  final Color surfaceColor;
  final Widget child;

  static const double _fadeExtent = AppSpacing.s4;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        final fadeRatio = (_fadeExtent / bounds.shortestSide).clamp(0.0, 0.5);

        if (axis == Axis.vertical) {
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              canFadeTowardStart
                  ? surfaceColor.withValues(alpha: 0)
                  : surfaceColor,
              surfaceColor,
              surfaceColor,
              canFadeTowardEnd
                  ? surfaceColor.withValues(alpha: 0)
                  : surfaceColor,
            ],
            stops: [0, fadeRatio, 1 - fadeRatio, 1],
          ).createShader(bounds);
        }

        final isRtl = Directionality.of(context) == TextDirection.rtl;
        final start = isRtl ? Alignment.centerRight : Alignment.centerLeft;
        final end = isRtl ? Alignment.centerLeft : Alignment.centerRight;

        return LinearGradient(
          begin: start,
          end: end,
          colors: [
            canFadeTowardStart
                ? surfaceColor.withValues(alpha: 0)
                : surfaceColor,
            surfaceColor,
            surfaceColor,
            canFadeTowardEnd
                ? surfaceColor.withValues(alpha: 0)
                : surfaceColor,
          ],
          stops: [0, fadeRatio, 1 - fadeRatio, 1],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}
