import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Tooltip placement relative to the trigger (web `side`).
enum TooltipSide { top, right, bottom, left }

/// Cross-axis alignment of tooltip content (web `align`).
enum TooltipAlign { start, center, end }

/// Application-owned tooltip wrapper (web `Tooltip`).
///
/// Renders message and rich content through a composited overlay with
/// fade-scale motion via [AppMotion], avoiding Material [Tooltip]'s
/// `OverlayPortal` deferred layout (unsafe inside scroll views).
class AppTooltip extends StatefulWidget {
  const AppTooltip({
    required this.child,
    this.message,
    this.content,
    this.side = TooltipSide.top,
    this.align = TooltipAlign.center,
    this.showArrow = true,
    this.disabled = false,
    this.preferBelow,
    this.delay = const Duration(milliseconds: 400),
    super.key,
  }) : assert(message != null || content != null);

  final Widget child;
  final String? message;
  final Widget? content;
  final TooltipSide side;
  final TooltipAlign align;
  final bool showArrow;
  final bool disabled;
  final Duration delay;

  /// When `false`, the Material fast-path tooltip prefers appearing above the trigger.
  final bool? preferBelow;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> with SingleTickerProviderStateMixin {
  static const _sideOffset = 6.0;

  final LayerLink _layerLink = LayerLink();
  final GlobalKey _triggerKey = GlobalKey();

  OverlayEntry? _overlayEntry;
  late final AnimationController _controller;
  Timer? _showTimer;
  Timer? _hideTimer;
  var _isHovering = false;

  bool get _overlayLinkActive {
    final leader = _layerLink.leader;
    return leader != null && leader.attached;
  }

  TooltipSide get _effectiveSide {
    if (widget.content != null) {
      return widget.side;
    }
    if (widget.preferBelow == true) {
      return TooltipSide.bottom;
    }
    return TooltipSide.top;
  }

  Widget get _tooltipContent => widget.content ?? Text(widget.message!);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.resolveDuration(AppMotionPreset.fadeScale),
    );
    FocusManager.instance.addListener(_handleGlobalFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleGlobalFocusChange);
    _cancelTimers();
    _removeOverlay(immediate: true);
    _controller.dispose();
    super.dispose();
  }

  void _cancelTimers() {
    _showTimer?.cancel();
    _showTimer = null;
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _handleGlobalFocusChange() {
    if (!mounted) return;
    if (_isHovering || _triggerHasFocus()) {
      _scheduleShow();
    } else {
      _scheduleHide();
    }
  }

  bool _triggerHasFocus() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final triggerContext = _triggerKey.currentContext;
    if (primaryFocus == null || triggerContext == null) return false;
    final focusContext = primaryFocus.context;
    if (focusContext == null) return false;

    var found = false;
    focusContext.visitAncestorElements((element) {
      if (element == triggerContext) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  void _onHoverEnter() {
    _isHovering = true;
    _scheduleShow();
  }

  void _onHoverExit() {
    _isHovering = false;
    _scheduleHide();
  }

  void _scheduleShow() {
    if (widget.disabled) return;
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_overlayEntry != null) return;
    _showTimer?.cancel();
    _showTimer = Timer(widget.delay, () {
      if (!mounted || widget.disabled) return;
      if (!_isHovering && !_triggerHasFocus()) return;
      _open();
    });
  }

  void _scheduleHide() {
    _showTimer?.cancel();
    _showTimer = null;
    if (_overlayEntry == null) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      if (_isHovering || _triggerHasFocus()) return;
      _close();
    });
  }

  void _open() {
    _showOverlay();
    _controller.forward(from: 0);
  }

  void _close() {
    _controller.reverse().whenComplete(() {
      if (!_isHovering && !_triggerHasFocus()) {
        _removeOverlay();
      }
    });
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = _createOverlayEntry();
    // Always insert into the app root overlay. Nested [Overlay.wrap] overlays use
    // a different layer coordinate space and break [CompositedTransformFollower]
    // positioning for triggers rendered in their child subtree.
    final overlay = Overlay.of(context, rootOverlay: true);
    overlay.insert(_overlayEntry!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _overlayEntry?.markNeedsBuild();
    });
  }

  void _removeOverlay({bool immediate = false}) {
    final entry = _overlayEntry;
    if (entry == null) return;
    _overlayEntry = null;
    entry.remove();
    if (immediate) {
      _controller.value = 0;
    }
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (overlayContext) {
        if (!_overlayLinkActive) {
          return const SizedBox.shrink();
        }

        final direction = Directionality.of(overlayContext);
        final (targetAnchor, followerAnchor, offset) = _anchorsFor(
          _effectiveSide,
          widget.align,
          direction,
        );

        return IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CompositedTransformFollower(
                link: _layerLink,
                offset: offset,
                targetAnchor: targetAnchor,
                followerAnchor: followerAnchor,
                showWhenUnlinked: false,
                child: AppMotion.animatedPreset(
                  context: overlayContext,
                  preset: AppMotionPreset.fadeScale,
                  animation: _controller,
                  child: _TooltipSurface(
                    side: _effectiveSide,
                    showArrow: widget.showArrow,
                    child: _tooltipContent,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  static (Alignment targetAnchor, Alignment followerAnchor, Offset offset) _anchorsFor(
    TooltipSide side,
    TooltipAlign align,
    TextDirection direction,
  ) {
    return switch (side) {
      TooltipSide.top => (
          _horizontalTarget(align, direction, vertical: -1),
          _horizontalFollower(align, direction, vertical: 1),
          const Offset(0, -_sideOffset),
        ),
      TooltipSide.bottom => (
          _horizontalTarget(align, direction, vertical: 1),
          _horizontalFollower(align, direction, vertical: -1),
          const Offset(0, _sideOffset),
        ),
      TooltipSide.left => (
          _verticalTarget(align, horizontal: -1),
          _verticalFollower(align, horizontal: 1),
          const Offset(-_sideOffset, 0),
        ),
      TooltipSide.right => (
          _verticalTarget(align, horizontal: 1),
          _verticalFollower(align, horizontal: -1),
          const Offset(_sideOffset, 0),
        ),
    };
  }

  static Alignment _horizontalTarget(TooltipAlign align, TextDirection direction, {required int vertical}) {
    final y = vertical.toDouble();
    return switch (align) {
      TooltipAlign.start => Alignment(direction == TextDirection.rtl ? 1 : -1, y),
      TooltipAlign.center => Alignment(0, y),
      TooltipAlign.end => Alignment(direction == TextDirection.rtl ? -1 : 1, y),
    };
  }

  static Alignment _horizontalFollower(TooltipAlign align, TextDirection direction, {required int vertical}) {
    final y = vertical.toDouble();
    return switch (align) {
      TooltipAlign.start => Alignment(direction == TextDirection.rtl ? 1 : -1, y),
      TooltipAlign.center => Alignment(0, y),
      TooltipAlign.end => Alignment(direction == TextDirection.rtl ? -1 : 1, y),
    };
  }

  static Alignment _verticalTarget(TooltipAlign align, {required int horizontal}) {
    final x = horizontal.toDouble();
    return switch (align) {
      TooltipAlign.start => Alignment(x, -1),
      TooltipAlign.center => Alignment(x, 0),
      TooltipAlign.end => Alignment(x, 1),
    };
  }

  static Alignment _verticalFollower(TooltipAlign align, {required int horizontal}) {
    final x = horizontal.toDouble();
    return switch (align) {
      TooltipAlign.start => Alignment(x, -1),
      TooltipAlign.center => Alignment(x, 0),
      TooltipAlign.end => Alignment(x, 1),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.disabled) {
      return widget.child;
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: KeyedSubtree(
        key: _triggerKey,
        child: MouseRegion(
          onEnter: (_) => _onHoverEnter(),
          onExit: (_) => _onHoverExit(),
          child: widget.child,
        ),
      ),
    );
  }
}

class _TooltipSurface extends StatelessWidget {
  const _TooltipSurface({
    required this.child,
    required this.side,
    required this.showArrow,
  });

  final Widget child;
  final TooltipSide side;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: elevation.decoration(
              level: 2,
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colors.borderSubtle),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space3,
              vertical: AppSpacing.space2,
            ),
            child: DefaultTextStyle(
              style: AppTypography.body(context).copyWith(color: colors.textPrimary),
              child: child,
            ),
          ),
          if (showArrow) _TooltipArrow(side: side, color: colors.surfaceRaised),
        ],
      ),
    );
  }
}

class _TooltipArrow extends StatelessWidget {
  const _TooltipArrow({required this.side, required this.color});

  final TooltipSide side;
  final Color color;

  static const _width = 10.0;
  static const _height = 5.0;

  @override
  Widget build(BuildContext context) {
    final (alignment, offset) = switch (side) {
      TooltipSide.top => (Alignment.bottomCenter, const Offset(0, _height)),
      TooltipSide.bottom => (Alignment.topCenter, const Offset(0, -_height)),
      TooltipSide.left => (Alignment.centerRight, const Offset(_height, 0)),
      TooltipSide.right => (Alignment.centerLeft, const Offset(-_height, 0)),
    };

    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Transform.translate(
          offset: offset,
          child: CustomPaint(
            size: side == TooltipSide.left || side == TooltipSide.right
                ? const Size(_height, _width)
                : const Size(_width, _height),
            painter: _TooltipArrowPainter(side: side, color: color),
          ),
        ),
      ),
    );
  }
}

class _TooltipArrowPainter extends CustomPainter {
  const _TooltipArrowPainter({required this.side, required this.color});

  final TooltipSide side;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    switch (side) {
      case TooltipSide.top:
        path
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width / 2, size.height)
          ..close();
      case TooltipSide.bottom:
        path
          ..moveTo(0, size.height)
          ..lineTo(size.width, size.height)
          ..lineTo(size.width / 2, 0)
          ..close();
      case TooltipSide.left:
        path
          ..moveTo(0, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(0, size.height)
          ..close();
      case TooltipSide.right:
        path
          ..moveTo(size.width, 0)
          ..lineTo(0, size.height / 2)
          ..lineTo(size.width, size.height)
          ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TooltipArrowPainter oldDelegate) {
    return oldDelegate.side != side || oldDelegate.color != color;
  }
}
