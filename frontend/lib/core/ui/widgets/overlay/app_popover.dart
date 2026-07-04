import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Which side of the trigger the popover opens toward.
enum AppPopoverSide { top, bottom, start, end }

/// Cross-axis alignment relative to the trigger.
enum AppPopoverAlign { start, center, end }

/// Combined placement for [AppPopover].
@immutable
class AppPopoverPlacement {
  const AppPopoverPlacement({this.side = AppPopoverSide.bottom, this.align = AppPopoverAlign.start});

  final AppPopoverSide side;
  final AppPopoverAlign align;
}

typedef AppPopoverContentBuilder = Widget Function(BuildContext context, VoidCallback hide);

/// Imperative handle returned by [AppPopover.show].
class AppPopoverHandle {
  const AppPopoverHandle._(this.dismiss);

  final VoidCallback dismiss;
}

/// Overlay-anchored popover with fade-scale motion and RTL-aware placement.
class AppPopover extends StatefulWidget {
  AppPopover({
    super.key,
    required this.trigger,
    AppPopoverContentBuilder? contentBuilder,
    this.content,
    this.placement = const AppPopoverPlacement(),
    this.open,
    this.onOpenChange,
    this.sideOffset = AppSpacing.s1,
    this.minWidth,
    this.matchTriggerWidth = false,
    this.contentPadding,
    this.dismissOnTapOutside = true,
  }) : assert(contentBuilder != null || content != null, 'Provide contentBuilder or content'),
       contentBuilder =
           contentBuilder ??
           ((context, hide) => Padding(padding: contentPadding ?? EdgeInsets.zero, child: content as Widget));

  final Widget trigger;
  final AppPopoverContentBuilder contentBuilder;
  final Widget? content;
  final AppPopoverPlacement placement;
  final bool? open;
  final ValueChanged<bool>? onOpenChange;
  final double sideOffset;
  final double? minWidth;
  final bool matchTriggerWidth;
  final EdgeInsets? contentPadding;
  final bool dismissOnTapOutside;

  static final Map<Object, _AppPopoverOverlay> _activeOverlays = {};

  /// Shows a popover anchored to [triggerContext].
  static AppPopoverHandle? show({
    required BuildContext context,
    required BuildContext triggerContext,
    required AppPopoverContentBuilder contentBuilder,
    AppPopoverPlacement placement = const AppPopoverPlacement(),
    double sideOffset = AppSpacing.s1,
    double? minWidth,
    bool dismissOnTapOutside = true,
    Object? groupId,
    bool reducedMotion = false,
  }) {
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    final renderBox = triggerContext.findRenderObject() as RenderBox?;
    if (overlayState == null || renderBox == null || !renderBox.hasSize) {
      return null;
    }

    final key = groupId ?? triggerContext;
    _activeOverlays[key]?.dispose();

    late _AppPopoverOverlay overlay;
    overlay = _AppPopoverOverlay(
      overlayState: overlayState,
      triggerRenderBox: renderBox,
      contentBuilder: contentBuilder,
      placement: placement,
      sideOffset: sideOffset,
      minWidth: minWidth,
      dismissOnTapOutside: dismissOnTapOutside,
      reducedMotion: reducedMotion || AppMotion.isReducedMotion(context),
      onDismissed: () => _activeOverlays.remove(key),
    );
    _activeOverlays[key] = overlay;
    overlay.show();
    return AppPopoverHandle._(overlay.hide);
  }

  /// Hides the popover associated with [groupId] or [triggerContext].
  static void hide({BuildContext? triggerContext, Object? groupId}) {
    final key = groupId ?? triggerContext;
    if (key == null) return;
    _activeOverlays.remove(key)?.hide();
  }

  @override
  State<AppPopover> createState() => _AppPopoverState();
}

class _AppPopoverState extends State<AppPopover> with SingleTickerProviderStateMixin {
  final GlobalKey _triggerKey = GlobalKey();
  OverlayEntry? _entry;
  late bool _open;
  late final AnimationController _controller;

  bool get _isControlled => widget.open != null;

  @override
  void initState() {
    super.initState();
    _open = widget.open ?? false;
    _controller = AnimationController(vsync: this);
    if (_open) {
      _scheduleOverlaySync();
    }
  }

  @override
  void didUpdateWidget(AppPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isControlled && widget.open != oldWidget.open) {
      _open = widget.open!;
      _scheduleOverlaySync();
    }
  }

  @override
  void dispose() {
    _removeOverlay(immediate: true);
    _controller.dispose();
    super.dispose();
  }

  void _setOpen(bool value) => _syncOpen(value);

  void _scheduleOverlaySync() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_open) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    });
  }

  void _syncOpen(bool value, {bool notify = true}) {
    if (_open == value) return;
    setState(() => _open = value);
    if (notify) widget.onOpenChange?.call(value);
    _scheduleOverlaySync();
  }

  void _toggle() => _setOpen(!_open);

  void _showOverlay() {
    if (_entry != null) return;
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    final renderBox = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayState == null || renderBox == null || !renderBox.hasSize) return;

    final resolvedMinWidth = widget.matchTriggerWidth ? renderBox.size.width : widget.minWidth;

    _entry = OverlayEntry(
      builder: (overlayContext) {
        return _AppPopoverOverlayLayer(
          triggerRenderBox: renderBox,
          placement: widget.placement,
          sideOffset: widget.sideOffset,
          minWidth: resolvedMinWidth,
          dismissOnTapOutside: widget.dismissOnTapOutside,
          controller: _controller,
          onRequestHide: () => _setOpen(false),
          child: widget.contentBuilder(overlayContext, () => _setOpen(false)),
        );
      },
    );
    overlayState.insert(_entry!);
    _runShowAnimation();
  }

  void _removeOverlay({bool immediate = false}) {
    final entry = _entry;
    if (entry == null) return;
    if (immediate) {
      entry.remove();
      _entry = null;
      _controller.reset();
      return;
    }
    _runHideAnimation(
      onComplete: () {
        entry.remove();
        if (mounted) {
          setState(() => _entry = null);
        } else {
          _entry = null;
        }
        _controller.reset();
      },
    );
  }

  void _runShowAnimation() {
    final reduced = AppMotion.isReducedMotion(context);
    final transition = AppMotion.resolveTransition(preset: AppMotionPreset.fadeScale, reducedMotion: reduced);
    _controller.duration = transition.duration;
    _controller.forward(from: 0);
  }

  void _runHideAnimation({required VoidCallback onComplete}) {
    final reduced = AppMotion.isReducedMotion(context);
    final transition = AppMotion.resolveTransition(preset: AppMotionPreset.fadeScale, reducedMotion: reduced);
    _controller.duration = transition.duration;
    _controller.reverse().whenComplete(onComplete);
  }

  void _handleTriggerTap() {
    if (_isControlled) {
      widget.onOpenChange?.call(!widget.open!);
      return;
    }
    _toggle();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _triggerKey,
      behavior: HitTestBehavior.opaque,
      onTap: _handleTriggerTap,
      child: widget.trigger,
    );
  }
}

class _AppPopoverOverlay {
  _AppPopoverOverlay({
    required this.overlayState,
    required this.triggerRenderBox,
    required this.contentBuilder,
    required this.placement,
    required this.sideOffset,
    required this.minWidth,
    required this.dismissOnTapOutside,
    required this.reducedMotion,
    required this.onDismissed,
  });

  final OverlayState overlayState;
  final RenderBox triggerRenderBox;
  final AppPopoverContentBuilder contentBuilder;
  final AppPopoverPlacement placement;
  final double sideOffset;
  final double? minWidth;
  final bool dismissOnTapOutside;
  final bool reducedMotion;
  final VoidCallback onDismissed;

  OverlayEntry? _entry;
  late final AnimationController _controller = AnimationController(vsync: _StandaloneTicker());

  void show() {
    _entry = OverlayEntry(
      builder: (overlayContext) {
        return _AppPopoverOverlayLayer(
          triggerRenderBox: triggerRenderBox,
          placement: placement,
          sideOffset: sideOffset,
          minWidth: minWidth,
          dismissOnTapOutside: dismissOnTapOutside,
          controller: _controller,
          onRequestHide: hide,
          child: contentBuilder(overlayContext, hide),
        );
      },
    );
    overlayState.insert(_entry!);
    _controller.duration = AppMotion.resolveTransition(
      preset: AppMotionPreset.fadeScale,
      reducedMotion: reducedMotion,
    ).duration;
    _controller.forward(from: 0);
  }

  void hide() {
    final entry = _entry;
    if (entry == null) return;
    _controller.reverse().whenComplete(() {
      entry.remove();
      _entry = null;
      _controller.dispose();
      onDismissed();
    });
  }

  void dispose() => hide();
}

class _AppPopoverOverlayLayer extends StatelessWidget {
  const _AppPopoverOverlayLayer({
    required this.triggerRenderBox,
    required this.placement,
    required this.sideOffset,
    required this.minWidth,
    required this.dismissOnTapOutside,
    required this.controller,
    required this.onRequestHide,
    required this.child,
  });

  final RenderBox triggerRenderBox;
  final AppPopoverPlacement placement;
  final double sideOffset;
  final double? minWidth;
  final bool dismissOnTapOutside;
  final AnimationController controller;
  final VoidCallback onRequestHide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.isReducedMotion(context);
    final transition = AppMotion.resolveTransition(preset: AppMotionPreset.fadeScale, reducedMotion: reduced);
    final direction = Directionality.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final triggerOffset = triggerRenderBox.localToGlobal(Offset.zero);
    final triggerSize = triggerRenderBox.size;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (dismissOnTapOutside)
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: onRequestHide),
          ),
        _AppPopoverPositionedContent(
          triggerOffset: triggerOffset,
          triggerSize: triggerSize,
          placement: placement,
          sideOffset: sideOffset,
          minWidth: minWidth,
          viewport: viewport,
          direction: direction,
          child: AnimatedBuilder(
            animation: CurvedAnimation(parent: controller, curve: transition.curve),
            builder: (context, child) {
              final t = controller.value;
              final hidden = AppMotion.hiddenValues(AppMotionPreset.fadeScale, direction: direction);
              final visible = AppMotion.visibleValues;
              final values = hidden.lerp(visible, t);
              return Opacity(
                opacity: values.opacity,
                child: Transform.scale(
                  scale: values.scale,
                  alignment: _scaleAlignment(placement, direction),
                  child: child,
                ),
              );
            },
            child: _AppPopoverSurface(minWidth: minWidth, maxWidth: viewport.width - AppSpacing.s2 * 2, child: child),
          ),
        ),
      ],
    );
  }

  static Alignment _scaleAlignment(AppPopoverPlacement placement, TextDirection direction) {
    return switch (placement.side) {
      AppPopoverSide.top => switch (placement.align) {
        AppPopoverAlign.start => direction == TextDirection.ltr ? Alignment.bottomLeft : Alignment.bottomRight,
        AppPopoverAlign.center => Alignment.bottomCenter,
        AppPopoverAlign.end => direction == TextDirection.ltr ? Alignment.bottomRight : Alignment.bottomLeft,
      },
      AppPopoverSide.bottom => switch (placement.align) {
        AppPopoverAlign.start => direction == TextDirection.ltr ? Alignment.topLeft : Alignment.topRight,
        AppPopoverAlign.center => Alignment.topCenter,
        AppPopoverAlign.end => direction == TextDirection.ltr ? Alignment.topRight : Alignment.topLeft,
      },
      AppPopoverSide.start => switch (placement.align) {
        AppPopoverAlign.start => direction == TextDirection.ltr ? Alignment.centerRight : Alignment.centerLeft,
        AppPopoverAlign.center => Alignment.center,
        AppPopoverAlign.end => direction == TextDirection.ltr ? Alignment.bottomRight : Alignment.bottomLeft,
      },
      AppPopoverSide.end => switch (placement.align) {
        AppPopoverAlign.start => direction == TextDirection.ltr ? Alignment.centerLeft : Alignment.centerRight,
        AppPopoverAlign.center => Alignment.center,
        AppPopoverAlign.end => direction == TextDirection.ltr ? Alignment.bottomLeft : Alignment.bottomRight,
      },
    };
  }
}

class _AppPopoverPositionedContent extends StatefulWidget {
  const _AppPopoverPositionedContent({
    required this.triggerOffset,
    required this.triggerSize,
    required this.placement,
    required this.sideOffset,
    required this.minWidth,
    required this.viewport,
    required this.direction,
    required this.child,
  });

  final Offset triggerOffset;
  final Size triggerSize;
  final AppPopoverPlacement placement;
  final double sideOffset;
  final double? minWidth;
  final Size viewport;
  final TextDirection direction;
  final Widget child;

  @override
  State<_AppPopoverPositionedContent> createState() => _AppPopoverPositionedContentState();
}

class _AppPopoverPositionedContentState extends State<_AppPopoverPositionedContent> {
  final GlobalKey _contentKey = GlobalKey();
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePosition());
  }

  @override
  void didUpdateWidget(_AppPopoverPositionedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePosition());
  }

  void _updatePosition() {
    final renderBox = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final contentSize = renderBox.size;
    final next = _computeOffset(contentSize);
    if (next != _offset) {
      setState(() => _offset = next);
    }
  }

  Offset _computeOffset(Size contentSize) {
    final triggerTopLeft = widget.triggerOffset;
    final triggerSize = widget.triggerSize;
    final side = widget.placement.side;
    final align = widget.placement.align;
    final gap = widget.sideOffset;
    final isRtl = widget.direction == TextDirection.rtl;

    double left;
    double top;

    switch (side) {
      case AppPopoverSide.bottom:
        top = triggerTopLeft.dy + triggerSize.height + gap;
        left = _alignHorizontal(triggerTopLeft.dx, triggerSize.width, contentSize.width, align, isRtl);
      case AppPopoverSide.top:
        top = triggerTopLeft.dy - contentSize.height - gap;
        left = _alignHorizontal(triggerTopLeft.dx, triggerSize.width, contentSize.width, align, isRtl);
      case AppPopoverSide.start:
        left = isRtl ? triggerTopLeft.dx + triggerSize.width + gap : triggerTopLeft.dx - contentSize.width - gap;
        top = _alignVertical(triggerTopLeft.dy, triggerSize.height, contentSize.height, align);
      case AppPopoverSide.end:
        left = isRtl ? triggerTopLeft.dx - contentSize.width - gap : triggerTopLeft.dx + triggerSize.width + gap;
        top = _alignVertical(triggerTopLeft.dy, triggerSize.height, contentSize.height, align);
    }

    left = left.clamp(
      AppSpacing.s2,
      math.max(AppSpacing.s2, widget.viewport.width - contentSize.width - AppSpacing.s2),
    );
    top = top.clamp(
      AppSpacing.s2,
      math.max(AppSpacing.s2, widget.viewport.height - contentSize.height - AppSpacing.s2),
    );

    return Offset(left, top);
  }

  static double _alignHorizontal(
    double triggerLeft,
    double triggerWidth,
    double contentWidth,
    AppPopoverAlign align,
    bool isRtl,
  ) {
    return switch (align) {
      AppPopoverAlign.start => isRtl ? triggerLeft + triggerWidth - contentWidth : triggerLeft,
      AppPopoverAlign.center => triggerLeft + (triggerWidth - contentWidth) / 2,
      AppPopoverAlign.end => isRtl ? triggerLeft : triggerLeft + triggerWidth - contentWidth,
    };
  }

  static double _alignVertical(double triggerTop, double triggerHeight, double contentHeight, AppPopoverAlign align) {
    return switch (align) {
      AppPopoverAlign.start => triggerTop,
      AppPopoverAlign.center => triggerTop + (triggerHeight - contentHeight) / 2,
      AppPopoverAlign.end => triggerTop + triggerHeight - contentHeight,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: KeyedSubtree(key: _contentKey, child: widget.child),
    );
  }
}

class _AppPopoverSurface extends StatelessWidget {
  const _AppPopoverSurface({required this.child, this.minWidth, this.maxWidth});

  final Widget child;
  final double? minWidth;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final elevation = context.elevation;
    final resolvedMinWidth = minWidth ?? 0;
    final resolvedMaxWidth = math.max(resolvedMinWidth, maxWidth ?? resolvedMinWidth);

    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: colors.borderDefault),
          boxShadow: elevation.level2,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: resolvedMinWidth, maxWidth: resolvedMaxWidth),
          child: minWidth != null ? SizedBox(width: minWidth, child: child) : IntrinsicWidth(child: child),
        ),
      ),
    );
  }
}

class _StandaloneTicker implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) {
    return Ticker(onTick, debugLabel: 'AppPopover.standalone');
  }
}
