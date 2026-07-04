import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/theme_context.dart';
import 'package:ai_clinic/core/ui/tokens/app_durations.dart';
import 'package:ai_clinic/core/ui/tokens/app_radii.dart';
import 'package:ai_clinic/core/ui/tokens/app_shadows.dart';
import 'package:ai_clinic/core/ui/tokens/app_spacing.dart';

/// Web `TooltipProvider` uses a ~400ms open delay; composed from duration tokens.
final Duration _kTooltipShowDelay = AppDurations.base + AppDurations.fast + AppDurations.instant;

/// Placement side for [AppTooltip].
///
/// `left` and `right` swap in RTL so the tooltip stays on the logical side.
enum AppTooltipSide { top, right, bottom, left }

/// Cross-axis alignment for [AppTooltip].
enum AppTooltipAlign { start, center, end }

/// Brief supplementary text on hover or keyboard focus.
///
/// No [AppTooltipProvider] is required — each instance self-manages its delay
/// and overlay lifecycle (unlike the web Radix provider).
class AppTooltip extends StatefulWidget {
  /// Wraps [child] and shows [message] on hover/focus.
  const AppTooltip({
    required this.message,
    required this.child,
    this.side = AppTooltipSide.top,
    this.align = AppTooltipAlign.center,
    this.showArrow = true,
    this.disabled = false,
    this.sideOffset = AppSpacing.s1 + AppSpacing.s0_5,
    this.collisionPadding = AppSpacing.s2,
    super.key,
  }) : content = null;

  /// Wraps [child] and shows rich [content] on hover/focus.
  const AppTooltip.rich({
    required this.content,
    required this.child,
    this.side = AppTooltipSide.top,
    this.align = AppTooltipAlign.center,
    this.showArrow = true,
    this.disabled = false,
    this.sideOffset = AppSpacing.s1 + AppSpacing.s0_5,
    this.collisionPadding = AppSpacing.s2,
    super.key,
  }) : message = null;

  final String? message;
  final Widget? content;
  final Widget child;
  final AppTooltipSide side;
  final AppTooltipAlign align;
  final bool showArrow;
  final bool disabled;
  final double sideOffset;
  final double collisionPadding;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _portalController = OverlayPortalController();
  final GlobalKey _targetKey = GlobalKey();

  Timer? _showTimer;
  bool _hovering = false;
  bool _focused = false;
  bool _visible = false;

  @override
  void dispose() {
    _cancelShowTimer();
    super.dispose();
  }

  void _cancelShowTimer() {
    _showTimer?.cancel();
    _showTimer = null;
  }

  void _scheduleShow() {
    _cancelShowTimer();
    _showTimer = Timer(_kTooltipShowDelay, () {
      if (!mounted) return;
      if (_hovering || _focused) {
        _show();
      }
    });
  }

  void _show() {
    if (_visible || widget.disabled) return;
    setState(() => _visible = true);
    _portalController.show();
  }

  void _hide() {
    _cancelShowTimer();
    if (!_visible) return;
    setState(() => _visible = false);
    _portalController.hide();
  }

  void _handleHover(bool hovering) {
    _hovering = hovering;
    if (hovering) {
      _scheduleShow();
    } else {
      _hide();
    }
  }

  void _handleFocus(bool focused) {
    _focused = focused;
    if (focused) {
      _scheduleShow();
    } else {
      _hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.disabled) {
      return widget.child;
    }

    final label = widget.message;
    final rich = widget.content;

    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (overlayContext) {
        return _AppTooltipOverlay(
          layerLink: _layerLink,
          targetKey: _targetKey,
          side: widget.side,
          align: widget.align,
          showArrow: widget.showArrow,
          sideOffset: widget.sideOffset,
          collisionPadding: widget.collisionPadding,
          child: Semantics(
            container: true,
            label: label,
            child: _AppTooltipPanel(
              showArrow: widget.showArrow,
              side: widget.side,
              child: rich ?? Text(label!, style: context.typography.bodySm.copyWith(color: context.colors.textPrimary)),
            ),
          ),
        );
      },
      child: Semantics(
        tooltip: label,
        child: Focus(
          onFocusChange: _handleFocus,
          skipTraversal: true,
          canRequestFocus: false,
          child: MouseRegion(
            onEnter: (_) => _handleHover(true),
            onExit: (_) => _handleHover(false),
            child: CompositedTransformTarget(key: _targetKey, link: _layerLink, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _AppTooltipPanel extends StatelessWidget {
  const _AppTooltipPanel({required this.child, required this.side, required this.showArrow});

  final Widget child;
  final AppTooltipSide side;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;

    return _AppTooltipFadeIn(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showArrow && side == AppTooltipSide.bottom) _TooltipArrow(color: colors.surfaceRaised, pointsDown: false),
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3, vertical: AppSpacing.s2),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: AppRadii.lgAll,
              border: Border.all(color: colors.borderSubtle),
              boxShadow: AppShadows.forLevel(2, brightness),
            ),
            child: child,
          ),
          if (showArrow && side == AppTooltipSide.top) _TooltipArrow(color: colors.surfaceRaised, pointsDown: true),
        ],
      ),
    );
  }
}

class _TooltipArrow extends StatelessWidget {
  const _TooltipArrow({required this.color, required this.pointsDown});

  final Color color;
  final bool pointsDown;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(10, 5),
      painter: _TooltipArrowPainter(color: color, pointsDown: pointsDown),
    );
  }
}

class _TooltipArrowPainter extends CustomPainter {
  _TooltipArrowPainter({required this.color, required this.pointsDown});

  final Color color;
  final bool pointsDown;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointsDown) {
      path
        ..moveTo(size.width / 2, size.height)
        ..lineTo(0, 0)
        ..lineTo(size.width, 0)
        ..close();
    } else {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TooltipArrowPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointsDown != pointsDown;
  }
}

/// Fade-in only (`duration-fast`); tooltip hides immediately (no exit animation).
class _AppTooltipFadeIn extends StatefulWidget {
  const _AppTooltipFadeIn({required this.child});

  final Widget child;

  @override
  State<_AppTooltipFadeIn> createState() => _AppTooltipFadeInState();
}

class _AppTooltipFadeInState extends State<_AppTooltipFadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  var _motionReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) {
      return;
    }
    _motionReady = true;
    final reduced = AppMotion.reduced(context);
    final spec = AppMotion.resolve(AppMotion.presets[AppMotionPreset.fadeScale]!, reduced: reduced);
    final duration = reduced ? spec.duration : AppDurations.fast;
    _controller = AnimationController(vsync: this, duration: duration);
    final curve = CurvedAnimation(parent: _controller, curve: spec.curve);
    _opacity = curve;
    _scale = Tween<double>(begin: reduced ? 1 : 0.98, end: 1).animate(curve);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(scale: _scale, alignment: Alignment.center, child: widget.child),
    );
  }
}

class _AppTooltipOverlay extends StatefulWidget {
  const _AppTooltipOverlay({
    required this.layerLink,
    required this.targetKey,
    required this.side,
    required this.align,
    required this.showArrow,
    required this.sideOffset,
    required this.collisionPadding,
    required this.child,
  });

  final LayerLink layerLink;
  final GlobalKey targetKey;
  final AppTooltipSide side;
  final AppTooltipAlign align;
  final bool showArrow;
  final double sideOffset;
  final double collisionPadding;
  final Widget child;

  @override
  State<_AppTooltipOverlay> createState() => _AppTooltipOverlayState();
}

class _AppTooltipOverlayState extends State<_AppTooltipOverlay> {
  final GlobalKey _panelKey = GlobalKey();
  AppTooltipSide? _resolvedSide;
  Offset _shift = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reposition());
  }

  void _reposition() {
    if (!mounted) return;
    final anchorBox = widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    final panelBox = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchorBox == null || panelBox == null || !anchorBox.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reposition());
      return;
    }

    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    final anchorTopLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchorSize = anchorBox.size;
    final panelSize = panelBox.size;
    final screen = overlayBox.size;
    final padding = widget.collisionPadding;

    var side = _resolvePhysicalSide(widget.side, context);

    final spaceBelow = screen.height - anchorTopLeft.dy - anchorSize.height;
    final spaceAbove = anchorTopLeft.dy;
    final spaceRight = screen.width - anchorTopLeft.dx - anchorSize.width;
    final spaceLeft = anchorTopLeft.dx;

    side = switch (side) {
      AppTooltipSide.bottom when panelSize.height > spaceBelow && spaceAbove > spaceBelow => AppTooltipSide.top,
      AppTooltipSide.top when panelSize.height > spaceAbove && spaceBelow > spaceAbove => AppTooltipSide.bottom,
      AppTooltipSide.right when panelSize.width > spaceRight && spaceLeft > spaceRight => AppTooltipSide.left,
      AppTooltipSide.left when panelSize.width > spaceLeft && spaceRight > spaceLeft => AppTooltipSide.right,
      _ => side,
    };

    final anchorPoint = _anchorPoint(side, anchorTopLeft, anchorSize);
    final followerPoint = _followerPoint(side, panelSize, widget.align);
    var panelTopLeft = anchorPoint - followerPoint;

    var dx = 0.0;
    var dy = 0.0;
    if (panelTopLeft.dx < padding) {
      dx = padding - panelTopLeft.dx;
    } else if (panelTopLeft.dx + panelSize.width > screen.width - padding) {
      dx = (screen.width - padding) - (panelTopLeft.dx + panelSize.width);
    }
    if (panelTopLeft.dy < padding) {
      dy = padding - panelTopLeft.dy;
    } else if (panelTopLeft.dy + panelSize.height > screen.height - padding) {
      dy = (screen.height - padding) - (panelTopLeft.dy + panelSize.height);
    }

    final newShift = Offset(dx, dy);
    if (_resolvedSide != side || _shift != newShift) {
      setState(() {
        _resolvedSide = side;
        _shift = newShift;
      });
    }
  }

  AppTooltipSide _resolvePhysicalSide(AppTooltipSide side, BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return switch (side) {
      AppTooltipSide.left => isRtl ? AppTooltipSide.right : AppTooltipSide.left,
      AppTooltipSide.right => isRtl ? AppTooltipSide.left : AppTooltipSide.right,
      _ => side,
    };
  }

  Offset _anchorPoint(AppTooltipSide side, Offset topLeft, Size size) {
    return switch (side) {
      AppTooltipSide.top => Offset(topLeft.dx + size.width / 2, topLeft.dy),
      AppTooltipSide.bottom => Offset(topLeft.dx + size.width / 2, topLeft.dy + size.height),
      AppTooltipSide.left => Offset(topLeft.dx, topLeft.dy + size.height / 2),
      AppTooltipSide.right => Offset(topLeft.dx + size.width, topLeft.dy + size.height / 2),
    };
  }

  Offset _followerPoint(AppTooltipSide side, Size panelSize, AppTooltipAlign align) {
    final cross = switch (align) {
      AppTooltipAlign.start => 0.0,
      AppTooltipAlign.center => 0.5,
      AppTooltipAlign.end => 1.0,
    };

    return switch (side) {
      AppTooltipSide.top => Offset(panelSize.width * cross, panelSize.height),
      AppTooltipSide.bottom => Offset(panelSize.width * cross, 0),
      AppTooltipSide.left => Offset(panelSize.width, panelSize.height * cross),
      AppTooltipSide.right => Offset(0, panelSize.height * cross),
    };
  }

  Alignment _targetAnchor(AppTooltipSide side) {
    return switch (side) {
      AppTooltipSide.top => Alignment.topCenter,
      AppTooltipSide.bottom => Alignment.bottomCenter,
      AppTooltipSide.left => Alignment.centerLeft,
      AppTooltipSide.right => Alignment.centerRight,
    };
  }

  Alignment _followerAnchor(AppTooltipSide side, AppTooltipAlign align) {
    final cross = switch (align) {
      AppTooltipAlign.start => -1.0,
      AppTooltipAlign.center => 0.0,
      AppTooltipAlign.end => 1.0,
    };

    return switch (side) {
      AppTooltipSide.top => Alignment(0, 1),
      AppTooltipSide.bottom => Alignment(0, -1),
      AppTooltipSide.left => Alignment(1, cross),
      AppTooltipSide.right => Alignment(-1, cross),
    };
  }

  @override
  Widget build(BuildContext context) {
    final side = _resolvedSide ?? _resolvePhysicalSide(widget.side, context);
    final arrowExtra = widget.showArrow ? AppSpacing.s0_5 : 0.0;

    return IgnorePointer(
      child: CompositedTransformFollower(
        link: widget.layerLink,
        targetAnchor: _targetAnchor(side),
        followerAnchor: _followerAnchor(side, widget.align),
        offset: _shift + Offset(0, widget.sideOffset + arrowExtra),
        showWhenUnlinked: false,
        child: Material(key: _panelKey, type: MaterialType.transparency, elevation: 0, child: widget.child),
      ),
    );
  }
}
