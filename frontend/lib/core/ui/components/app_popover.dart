import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Horizontal alignment of popover content relative to the trigger.
enum AppPopoverAlign { start, center, end }

/// Vertical placement of popover content relative to the trigger.
enum AppPopoverSide { top, bottom }

typedef AppPopoverTriggerBuilder = Widget Function(BuildContext context, bool isOpen, VoidCallback onToggle);

/// Minimum listbox popover width (web `w-80` / 20rem).
const appPopoverListboxMinWidth = 320.0;

/// Overlay-based popover aligned to a trigger (web `Popover`).
///
/// Content width matches the trigger by default, with fade-scale motion on open.
class AppPopover extends StatefulWidget {
  const AppPopover({
    required this.triggerBuilder,
    required this.child,
    this.open,
    this.onOpenChange,
    this.align = AppPopoverAlign.start,
    this.side = AppPopoverSide.bottom,
    this.flip = true,
    this.sideOffset = AppSpacing.space1,
    this.matchTriggerWidth = true,
    this.minWidth,
    this.width,
    this.estimatedContentHeight,
    super.key,
  });

  final AppPopoverTriggerBuilder triggerBuilder;
  final Widget child;
  final bool? open;
  final ValueChanged<bool>? onOpenChange;
  final AppPopoverAlign align;
  final AppPopoverSide side;

  /// When true, opens on the opposite [side] if there is not enough viewport space.
  final bool flip;
  final double sideOffset;
  final bool matchTriggerWidth;

  /// When set with [matchTriggerWidth], content is at least this wide (web `min-w-[trigger] w-80`).
  final double? minWidth;
  final double? width;

  /// Hint for first-frame flip before overlay content is measured.
  final double? estimatedContentHeight;

  @override
  State<AppPopover> createState() => _AppPopoverState();
}

class _AppPopoverState extends State<AppPopover> with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _triggerKey = GlobalKey();
  final GlobalKey _contentKey = GlobalKey();

  OverlayEntry? _overlayEntry;
  late final AnimationController _controller;
  bool? _internalOpen;
  double _triggerWidth = 0;
  var _overlayRefreshScheduled = false;
  var _isClosing = false;
  var _resolvedSide = AppPopoverSide.bottom;

  bool get _isOpen => widget.open ?? _internalOpen ?? false;

  bool get _overlayLinkActive {
    final leader = _layerLink.leader;
    return leader != null && leader.attached;
  }

  @override
  void initState() {
    super.initState();
    // Do not read inherited widgets (e.g. MediaQuery) from initState.
    _controller = AnimationController(vsync: this, duration: AppMotion.resolveDuration(AppMotionPreset.fadeScale));
    if (widget.open == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(notify: false));
    }
  }

  @override
  void didUpdateWidget(covariant AppPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open && widget.open != null) {
      final nextOpen = widget.open!;
      // Defer overlay/animation work — _controller.forward/reverse notify
      // listeners and must not run during the parent build phase.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.open != nextOpen) return;
        if (nextOpen) {
          _open(notify: false);
        } else {
          _close(notify: false);
        }
      });
    } else if (_isOpen) {
      // OverlayEntry does not rebuild when the parent rebuilds; refresh so
      // combobox/search results, loading, and empty states update live.
      // Defer — markNeedsBuild must not run during the parent build phase.
      _scheduleOverlayRefresh();
    }
  }

  void _scheduleOverlayRefresh() {
    if (_overlayRefreshScheduled || _isClosing) return;
    _overlayRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayRefreshScheduled = false;
      if (!mounted || !_isOpen || _isClosing) return;
      final entry = _overlayEntry;
      if (entry == null || !entry.mounted || !_overlayLinkActive) return;
      entry.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    // Remove the overlay without touching the animation controller — resetting
    // _controller.value during unmount notifies AnimatedBuilder listeners while
    // the widget tree is locked (sign-out / route teardown).
    final entry = _overlayEntry;
    _overlayEntry = null;
    entry?.remove();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    _setOpen(!_isOpen, notify: true);
  }

  void _setOpen(bool value, {required bool notify}) {
    if (_isOpen == value) return;
    if (value) {
      _open(notify: notify);
    } else {
      _close(notify: notify);
    }
  }

  void _open({bool notify = true}) {
    _isClosing = false;
    if (widget.open == null) {
      setState(() => _internalOpen = true);
    }
    if (notify) {
      widget.onOpenChange?.call(true);
    }
    _measureTriggerWidth();
    _resolvedSide = _resolveSide();
    _showOverlay();
    _controller.forward(from: 0);
    _scheduleSideReflow();
  }

  void _scheduleSideReflow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isOpen || _isClosing) return;
      final contentBox = _contentKey.currentContext?.findRenderObject() as RenderBox?;
      if (contentBox == null || !contentBox.hasSize) return;
      final nextSide = _resolveSide(contentHeight: contentBox.size.height);
      if (nextSide == _resolvedSide) return;
      _resolvedSide = nextSide;
      _overlayEntry?.markNeedsBuild();
    });
  }

  AppPopoverSide _resolveSide({double? contentHeight}) {
    final preferred = widget.side;
    if (!widget.flip) return preferred;

    final triggerBox = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (triggerBox == null || !triggerBox.hasSize) return preferred;

    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) return preferred;

    final triggerTopLeft = triggerBox.localToGlobal(Offset.zero);
    final triggerBottom = triggerTopLeft.dy + triggerBox.size.height;
    final viewportTop = mediaQuery.viewPadding.top;
    final viewportBottom = mediaQuery.size.height - mediaQuery.viewPadding.bottom;
    final height = contentHeight ?? widget.estimatedContentHeight ?? 200;
    final spaceBelow = viewportBottom - triggerBottom - widget.sideOffset;
    final spaceAbove = triggerTopLeft.dy - viewportTop - widget.sideOffset;

    return switch (preferred) {
      AppPopoverSide.bottom when spaceBelow < height && spaceAbove > spaceBelow => AppPopoverSide.top,
      AppPopoverSide.top when spaceAbove < height && spaceBelow > spaceAbove => AppPopoverSide.bottom,
      _ => preferred,
    };
  }

  void _close({bool notify = true}) {
    _overlayRefreshScheduled = false;
    _isClosing = true;
    if (widget.open == null) {
      setState(() => _internalOpen = false);
    }
    if (notify) {
      widget.onOpenChange?.call(false);
    }
    _controller.reverse().whenComplete(() {
      _isClosing = false;
      if (!_isOpen) {
        _removeOverlay();
      }
    });
  }

  void _measureTriggerWidth() {
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.attached && box.hasSize) {
      _triggerWidth = box.size.width;
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    final entry = _overlayEntry;
    if (entry == null) return;
    _overlayEntry = null;
    entry.remove();
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (overlayContext) {
        // CompositedTransformFollower calls getTransformTo on the leader;
        // skip when the trigger is detached (close animation, scroll-away, hot reload).
        if (!_overlayLinkActive) {
          return const SizedBox.shrink();
        }

        final direction = Directionality.of(overlayContext);
        final targetAnchor = _targetAnchor(widget.align, direction, _resolvedSide);
        final followerAnchor = _followerAnchor(widget.align, direction, _resolvedSide);
        final contentWidth = _resolveContentWidth();
        final offset = _resolvedSide == AppPopoverSide.bottom
            ? Offset(0, widget.sideOffset)
            : Offset(0, -widget.sideOffset);

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _setOpen(false, notify: true),
                  ),
                ),
                CompositedTransformFollower(
                  link: _layerLink,
                  offset: offset,
                  targetAnchor: targetAnchor,
                  followerAnchor: followerAnchor,
                  showWhenUnlinked: false,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Focus(
                      autofocus: true,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                          _setOpen(false, notify: true);
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: AppMotion.animatedPreset(
                        context: overlayContext,
                        preset: AppMotionPreset.fadeScale,
                        animation: _controller,
                        child: _PopoverSurface(key: _contentKey, width: contentWidth, child: widget.child),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  double? _resolveContentWidth() {
    if (widget.width != null) return widget.width;

    final triggerWidth = widget.matchTriggerWidth && _triggerWidth > 0 ? _triggerWidth : null;
    final minWidth = widget.minWidth;

    if (triggerWidth != null && minWidth != null) {
      return triggerWidth > minWidth ? triggerWidth : minWidth;
    }
    if (triggerWidth != null) return triggerWidth;
    if (minWidth != null) return minWidth;
    return null;
  }

  static Alignment _targetAnchor(AppPopoverAlign align, TextDirection direction, AppPopoverSide side) {
    final vertical = side == AppPopoverSide.bottom ? 1.0 : -1.0;
    return switch (align) {
      AppPopoverAlign.start => Alignment(direction == TextDirection.rtl ? 1 : -1, vertical),
      AppPopoverAlign.center => Alignment(0, vertical),
      AppPopoverAlign.end => Alignment(direction == TextDirection.rtl ? -1 : 1, vertical),
    };
  }

  static Alignment _followerAnchor(AppPopoverAlign align, TextDirection direction, AppPopoverSide side) {
    final vertical = side == AppPopoverSide.bottom ? -1.0 : 1.0;
    return switch (align) {
      AppPopoverAlign.start => Alignment(direction == TextDirection.rtl ? 1 : -1, vertical),
      AppPopoverAlign.center => Alignment(0, vertical),
      AppPopoverAlign.end => Alignment(direction == TextDirection.rtl ? -1 : 1, vertical),
    };
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: KeyedSubtree(key: _triggerKey, child: widget.triggerBuilder(context, _isOpen, _toggle)),
    );
  }
}

class _PopoverSurface extends StatelessWidget {
  const _PopoverSurface({required this.child, this.width, super.key});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        decoration: elevation.decoration(
          level: 2,
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
