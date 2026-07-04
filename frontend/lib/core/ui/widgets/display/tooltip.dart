import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

enum AppTooltipPlacement { top, bottom, left, right }

enum AppTooltipAlign { start, center, end }

/// Brief supplementary text on hover/focus via overlay.
class AppTooltip extends StatefulWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
    this.placement = AppTooltipPlacement.top,
    this.align = AppTooltipAlign.center,
    this.delay = const Duration(milliseconds: 400),
    this.showArrow = true,
    this.disabled = false,
  });

  final Widget message;
  final Widget child;
  final AppTooltipPlacement placement;
  final AppTooltipAlign align;
  final Duration delay;
  final bool showArrow;
  final bool disabled;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  OverlayEntry? _entry;
  Timer? _showTimer;
  final LayerLink _link = LayerLink();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _hide(immediate: true);
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleShow() {
    if (widget.disabled) return;
    _showTimer?.cancel();
    _showTimer = Timer(widget.delay, () {
      if (!mounted) return;
      _show();
    });
  }

  void _cancelShow() {
    _showTimer?.cancel();
    _showTimer = null;
  }

  void _show() {
    if (_entry != null || widget.disabled) return;

    _entry = OverlayEntry(
      builder: (overlayContext) {
        return _TooltipOverlay(
          link: _link,
          message: widget.message,
          placement: widget.placement,
          align: widget.align,
          showArrow: widget.showArrow,
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void _hide({bool immediate = false}) {
    _cancelShow();
    _entry?.remove();
    _entry = null;
    if (!immediate && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.disabled) return widget.child;

    return CompositedTransformTarget(
      link: _link,
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (focused) {
          if (focused) {
            _scheduleShow();
          } else {
            _hide();
          }
        },
        child: MouseRegion(
          onEnter: (_) => _scheduleShow(),
          onExit: (_) => _hide(),
          child: widget.child,
        ),
      ),
    );
  }
}

class _TooltipOverlay extends StatefulWidget {
  const _TooltipOverlay({
    required this.link,
    required this.message,
    required this.placement,
    required this.align,
    required this.showArrow,
  });

  final LayerLink link;
  final Widget message;
  final AppTooltipPlacement placement;
  final AppTooltipAlign align;
  final bool showArrow;

  @override
  State<_TooltipOverlay> createState() => _TooltipOverlayState();
}

class _TooltipOverlayState extends State<_TooltipOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    final reduced = AppMotion.isReducedMotion(context);
    final transition = AppMotion.resolve(
      duration: AppDurations.fast,
      curve: AppCurves.out,
      reducedMotion: reduced,
    );
    _controller = AnimationController(
      vsync: this,
      duration: transition.duration,
    );
    _fade = CurvedAnimation(parent: _controller, curve: transition.curve);
    _scale = Tween<double>(begin: 0.98, end: 1).animate(_fade);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final elevation = context.elevation;
    final offset = _offsetForPlacement();
    final followerAlign = _followerAlign();
    final targetAnchor = _targetAnchor();

    return Stack(
      children: [
        CompositedTransformFollower(
          link: widget.link,
          targetAnchor: targetAnchor,
          followerAnchor: followerAlign,
          offset: offset,
          showWhenUnlinked: false,
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      borderRadius: AppRadius.lgAll,
                      border: Border.all(color: colors.borderSubtle),
                      boxShadow: elevation.level2,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s3,
                        vertical: AppSpacing.s2,
                      ),
                      child: DefaultTextStyle(
                        style: context.typography.bodySm.copyWith(
                          color: colors.textPrimary,
                        ),
                        child: widget.message,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Alignment _targetAnchor() => switch (widget.placement) {
    AppTooltipPlacement.top => Alignment.topCenter,
    AppTooltipPlacement.bottom => Alignment.bottomCenter,
    AppTooltipPlacement.left => Alignment.centerLeft,
    AppTooltipPlacement.right => Alignment.centerRight,
  };

  Alignment _followerAlign() {
    final horizontal = switch (widget.align) {
      AppTooltipAlign.start => -1.0,
      AppTooltipAlign.center => 0.0,
      AppTooltipAlign.end => 1.0,
    };

    return switch (widget.placement) {
      AppTooltipPlacement.top => Alignment(horizontal, 1),
      AppTooltipPlacement.bottom => Alignment(horizontal, -1),
      AppTooltipPlacement.left => Alignment(1, horizontal),
      AppTooltipPlacement.right => Alignment(-1, horizontal),
    };
  }

  Offset _offsetForPlacement() {
    const gap = 6.0;
    return switch (widget.placement) {
      AppTooltipPlacement.top => const Offset(0, -gap),
      AppTooltipPlacement.bottom => const Offset(0, gap),
      AppTooltipPlacement.left => const Offset(-gap, 0),
      AppTooltipPlacement.right => const Offset(gap, 0),
    };
  }
}
