import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/theme_context.dart';
import 'package:ai_clinic/core/ui/tokens/app_radii.dart';
import 'package:ai_clinic/core/ui/tokens/app_shadows.dart';
import 'package:ai_clinic/core/ui/tokens/app_spacing.dart';

/// Logical placement for an [AppPopover] panel relative to its anchor.
///
/// `start` and `end` follow the ambient [TextDirection] (RTL-aware).
enum AppPopoverPlacement { bottomStart, bottomEnd, topStart, topEnd, bottom, top }

/// Drives [AppPopover] open state for imperative or controlled usage.
class AppPopoverController extends ChangeNotifier {
  AppPopoverController({bool initialOpen = false})
    : _portalController = OverlayPortalController(),
      _isOpen = initialOpen {
    if (initialOpen) {
      _portalController.show();
    }
  }

  final OverlayPortalController _portalController;

  bool _isOpen;

  /// Whether the popover panel is currently visible.
  bool get isOpen => _isOpen;

  OverlayPortalController get portalController => _portalController;

  /// Opens the popover panel.
  void show() {
    if (_isOpen) return;
    _isOpen = true;
    _portalController.show();
    notifyListeners();
  }

  /// Closes the popover panel.
  void hide() {
    if (!_isOpen) return;
    _isOpen = false;
    _portalController.hide();
    notifyListeners();
  }

  /// Toggles the popover panel.
  void toggle() {
    if (_isOpen) {
      hide();
    } else {
      show();
    }
  }
}

/// Anchored transient surface for lightweight forms, menus, and pickers.
///
/// Uses [CompositedTransformTarget] + [OverlayPortal] + [CompositedTransformFollower]
/// for lifecycle-safe positioning. Dismisses on outside tap, `Esc`, and route pop;
/// restores focus to the trigger on close.
class AppPopover extends StatefulWidget {
  const AppPopover({
    required this.trigger,
    required this.content,
    this.controller,
    this.placement = AppPopoverPlacement.bottomStart,
    this.matchAnchorWidth = false,
    this.sideOffset = AppSpacing.s1,
    this.collisionPadding = AppSpacing.s2,
    this.onOpenChange,
    super.key,
  });

  final AppPopoverController? controller;
  final Widget Function(BuildContext context, VoidCallback show, VoidCallback hide, VoidCallback toggle) trigger;
  final WidgetBuilder content;
  final AppPopoverPlacement placement;
  final bool matchAnchorWidth;
  final double sideOffset;
  final double collisionPadding;
  final ValueChanged<bool>? onOpenChange;

  @override
  State<AppPopover> createState() => _AppPopoverState();
}

class _AppPopoverState extends State<AppPopover> {
  late AppPopoverController _controller;
  late bool _ownsController;
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _anchorKey = GlobalKey();
  FocusNode? _focusBeforeOpen;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AppPopoverController();
    _controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant AppPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_handleControllerChange);
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? AppPopoverController();
      _controller.addListener(_handleControllerChange);
    }
  }

  @override
  void deactivate() {
    if (_controller.isOpen) {
      _controller.hide();
      widget.onOpenChange?.call(false);
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChange);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleControllerChange() {
    widget.onOpenChange?.call(_controller.isOpen);
    if (!_controller.isOpen) {
      _restoreFocus();
    }
  }

  void _show() {
    if (_controller.isOpen) return;
    _focusBeforeOpen = FocusManager.instance.primaryFocus;
    _controller.show();
    widget.onOpenChange?.call(true);
  }

  void _hide({bool restoreFocus = true}) {
    if (!_controller.isOpen) return;
    _controller.hide();
    widget.onOpenChange?.call(false);
    if (restoreFocus) {
      _restoreFocus();
    }
  }

  void _toggle() => _controller.isOpen ? _hide() : _show();

  void _restoreFocus() {
    final node = _focusBeforeOpen;
    _focusBeforeOpen = null;
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _controller.portalController,
      overlayChildBuilder: (overlayContext) {
        return _AppPopoverOverlay(
          layerLink: _layerLink,
          anchorKey: _anchorKey,
          placement: widget.placement,
          matchAnchorWidth: widget.matchAnchorWidth,
          sideOffset: widget.sideOffset,
          collisionPadding: widget.collisionPadding,
          onDismiss: _hide,
          child: widget.content(overlayContext),
        );
      },
      child: CompositedTransformTarget(
        key: _anchorKey,
        link: _layerLink,
        child: widget.trigger(context, _show, _hide, _toggle),
      ),
    );
  }
}

/// Imperatively shows a popover anchored to [anchorLink].
///
/// The anchor widget must be wrapped in [CompositedTransformTarget] with the
/// same [LayerLink]. Pass [anchorKey] when using [matchAnchorWidth] or
/// collision-aware repositioning. Returns when the popover is dismissed.
Future<void> showAppPopover({
  required BuildContext context,
  required LayerLink anchorLink,
  required Widget Function(BuildContext context, VoidCallback dismiss) builder,
  GlobalKey? anchorKey,
  AppPopoverPlacement placement = AppPopoverPlacement.bottomStart,
  bool matchAnchorWidth = false,
  double sideOffset = AppSpacing.s1,
  double collisionPadding = AppSpacing.s2,
}) {
  final overlayState = Overlay.of(context, rootOverlay: true);
  final completer = Completer<void>();
  late OverlayEntry entry;
  final focusBeforeOpen = FocusManager.instance.primaryFocus;
  var dismissed = false;

  void dismiss({bool restoreFocus = true}) {
    if (dismissed) return;
    dismissed = true;
    entry.remove();
    if (restoreFocus) {
      final node = focusBeforeOpen;
      if (node != null && node.canRequestFocus) {
        node.requestFocus();
      }
    }
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  entry = OverlayEntry(
    builder: (overlayContext) {
      return _AppPopoverOverlay(
        layerLink: anchorLink,
        anchorKey: anchorKey,
        placement: placement,
        matchAnchorWidth: matchAnchorWidth,
        sideOffset: sideOffset,
        collisionPadding: collisionPadding,
        onDismiss: dismiss,
        child: builder(overlayContext, dismiss),
      );
    },
  );

  overlayState.insert(entry);
  return completer.future;
}

class _AppPopoverOverlay extends StatefulWidget {
  const _AppPopoverOverlay({
    required this.layerLink,
    required this.placement,
    required this.matchAnchorWidth,
    required this.sideOffset,
    required this.collisionPadding,
    required this.onDismiss,
    required this.child,
    this.anchorKey,
  });

  final LayerLink layerLink;
  final GlobalKey? anchorKey;
  final AppPopoverPlacement placement;
  final bool matchAnchorWidth;
  final double sideOffset;
  final double collisionPadding;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_AppPopoverOverlay> createState() => _AppPopoverOverlayState();
}

class _AppPopoverOverlayState extends State<_AppPopoverOverlay> {
  final GlobalKey _panelKey = GlobalKey();
  AppPopoverPlacement? _resolvedPlacement;
  Offset _shift = Offset.zero;
  double? _anchorWidth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reposition());
  }

  void _reposition() {
    if (!mounted) return;

    final anchorBox = _anchorRenderBox;
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

    var placement = widget.placement;

    final spaceBelow = screen.height - anchorTopLeft.dy - anchorSize.height;
    final spaceAbove = anchorTopLeft.dy;
    final prefersBottom = _isBottomPlacement(placement);

    if (prefersBottom && panelSize.height + widget.sideOffset > spaceBelow && spaceAbove > spaceBelow) {
      placement = _flipVertical(placement);
    } else if (!_isBottomPlacement(placement) &&
        panelSize.height + widget.sideOffset > spaceAbove &&
        spaceBelow > spaceAbove) {
      placement = _flipVertical(placement);
    }

    final isBottom = _isBottomPlacement(placement);
    final anchorPoint = _anchorPoint(
      placement: placement,
      anchorTopLeft: anchorTopLeft,
      anchorSize: anchorSize,
      context: context,
    );
    final followerPoint = _followerPoint(placement: placement, panelSize: panelSize, context: context);

    var panelTopLeft = Offset(
      anchorPoint.dx - followerPoint.dx + widget.sideOffset * _horizontalSide(placement),
      isBottom ? anchorPoint.dy + widget.sideOffset : anchorPoint.dy - widget.sideOffset - panelSize.height,
    );

    var dx = 0.0;
    final panelLeft = panelTopLeft.dx;
    if (panelLeft < padding) {
      dx = padding - panelLeft;
    } else if (panelLeft + panelSize.width > screen.width - padding) {
      dx = (screen.width - padding) - (panelLeft + panelSize.width);
    }

    final newShift = Offset(dx, 0);
    final newPlacement = placement;
    final newAnchorWidth = widget.matchAnchorWidth ? anchorSize.width : null;

    if (_resolvedPlacement != newPlacement || _shift != newShift || _anchorWidth != newAnchorWidth) {
      setState(() {
        _resolvedPlacement = newPlacement;
        _shift = newShift;
        _anchorWidth = newAnchorWidth;
      });
    }
  }

  RenderBox? get _anchorRenderBox {
    final keyBox = widget.anchorKey?.currentContext?.findRenderObject();
    if (keyBox is RenderBox) return keyBox;
    return null;
  }

  bool _isBottomPlacement(AppPopoverPlacement placement) {
    return switch (placement) {
      AppPopoverPlacement.bottomStart || AppPopoverPlacement.bottomEnd || AppPopoverPlacement.bottom => true,
      AppPopoverPlacement.topStart || AppPopoverPlacement.topEnd || AppPopoverPlacement.top => false,
    };
  }

  AppPopoverPlacement _flipVertical(AppPopoverPlacement placement) {
    return switch (placement) {
      AppPopoverPlacement.bottomStart => AppPopoverPlacement.topStart,
      AppPopoverPlacement.bottomEnd => AppPopoverPlacement.topEnd,
      AppPopoverPlacement.bottom => AppPopoverPlacement.top,
      AppPopoverPlacement.topStart => AppPopoverPlacement.bottomStart,
      AppPopoverPlacement.topEnd => AppPopoverPlacement.bottomEnd,
      AppPopoverPlacement.top => AppPopoverPlacement.bottom,
    };
  }

  double _horizontalSide(AppPopoverPlacement placement) => 0.0;

  Offset _anchorPoint({
    required AppPopoverPlacement placement,
    required Offset anchorTopLeft,
    required Size anchorSize,
    required BuildContext context,
  }) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return switch (placement) {
      AppPopoverPlacement.bottomStart => Offset(
        anchorTopLeft.dx + (isRtl ? anchorSize.width : 0),
        anchorTopLeft.dy + anchorSize.height,
      ),
      AppPopoverPlacement.bottomEnd => Offset(
        anchorTopLeft.dx + (isRtl ? 0 : anchorSize.width),
        anchorTopLeft.dy + anchorSize.height,
      ),
      AppPopoverPlacement.topStart => Offset(anchorTopLeft.dx + (isRtl ? anchorSize.width : 0), anchorTopLeft.dy),
      AppPopoverPlacement.topEnd => Offset(anchorTopLeft.dx + (isRtl ? 0 : anchorSize.width), anchorTopLeft.dy),
      AppPopoverPlacement.bottom => Offset(
        anchorTopLeft.dx + anchorSize.width / 2,
        anchorTopLeft.dy + anchorSize.height,
      ),
      AppPopoverPlacement.top => Offset(anchorTopLeft.dx + anchorSize.width / 2, anchorTopLeft.dy),
    };
  }

  Offset _followerPoint({
    required AppPopoverPlacement placement,
    required Size panelSize,
    required BuildContext context,
  }) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return switch (placement) {
      AppPopoverPlacement.bottomStart => Offset(isRtl ? panelSize.width : 0, 0),
      AppPopoverPlacement.bottomEnd => Offset(isRtl ? 0 : panelSize.width, 0),
      AppPopoverPlacement.topStart => Offset(isRtl ? panelSize.width : 0, panelSize.height),
      AppPopoverPlacement.topEnd => Offset(isRtl ? 0 : panelSize.width, panelSize.height),
      AppPopoverPlacement.bottom => Offset(panelSize.width / 2, 0),
      AppPopoverPlacement.top => Offset(panelSize.width / 2, panelSize.height),
    };
  }

  Alignment _targetAnchor(AppPopoverPlacement placement) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return switch (placement) {
      AppPopoverPlacement.bottomStart => isRtl ? Alignment.bottomRight : Alignment.bottomLeft,
      AppPopoverPlacement.bottomEnd => isRtl ? Alignment.bottomLeft : Alignment.bottomRight,
      AppPopoverPlacement.topStart => isRtl ? Alignment.topRight : Alignment.topLeft,
      AppPopoverPlacement.topEnd => isRtl ? Alignment.topLeft : Alignment.topRight,
      AppPopoverPlacement.bottom => Alignment.bottomCenter,
      AppPopoverPlacement.top => Alignment.topCenter,
    };
  }

  Alignment _followerAnchor(AppPopoverPlacement placement) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return switch (placement) {
      AppPopoverPlacement.bottomStart => isRtl ? Alignment.topRight : Alignment.topLeft,
      AppPopoverPlacement.bottomEnd => isRtl ? Alignment.topLeft : Alignment.topRight,
      AppPopoverPlacement.topStart => isRtl ? Alignment.bottomRight : Alignment.bottomLeft,
      AppPopoverPlacement.topEnd => isRtl ? Alignment.bottomLeft : Alignment.bottomRight,
      AppPopoverPlacement.bottom => Alignment.topCenter,
      AppPopoverPlacement.top => Alignment.bottomCenter,
    };
  }

  @override
  Widget build(BuildContext context) {
    final placement = _resolvedPlacement ?? widget.placement;
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onDismiss();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: TapRegion(
              onTapOutside: (_) => widget.onDismiss(),
              child: const ColoredBox(color: Color(0x00000000)),
            ),
          ),
          Shortcuts(
            shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): _DismissPopoverIntent()},
            child: Actions(
              actions: {
                _DismissPopoverIntent: CallbackAction<_DismissPopoverIntent>(
                  onInvoke: (_) {
                    widget.onDismiss();
                    return null;
                  },
                ),
              },
              child: CompositedTransformFollower(
                link: widget.layerLink,
                targetAnchor: _targetAnchor(placement),
                followerAnchor: _followerAnchor(placement),
                offset: Offset(_shift.dx, widget.sideOffset),
                showWhenUnlinked: false,
                child: _AppPopoverFadeScale(
                  onLayout: _reposition,
                  child: Material(
                    key: _panelKey,
                    type: MaterialType.transparency,
                    child: Container(
                      width: _anchorWidth,
                      constraints: const BoxConstraints(maxWidth: 480),
                      decoration: BoxDecoration(
                        color: colors.surfaceRaised,
                        borderRadius: AppRadii.lgAll,
                        border: Border.all(color: colors.borderSubtle),
                        boxShadow: AppShadows.forLevel(2, brightness),
                      ),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DismissPopoverIntent extends Intent {
  const _DismissPopoverIntent();
}

/// Enter/exit wrapper using the `motion-fade-scale` preset.
class _AppPopoverFadeScale extends StatefulWidget {
  const _AppPopoverFadeScale({required this.child, this.onLayout});

  final Widget child;
  final VoidCallback? onLayout;

  @override
  State<_AppPopoverFadeScale> createState() => _AppPopoverFadeScaleState();
}

class _AppPopoverFadeScaleState extends State<_AppPopoverFadeScale> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final bool _reduced;
  var _motionReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionReady) {
      return;
    }
    _motionReady = true;
    _reduced = AppMotion.reduced(context);
    final enter = AppMotion.resolvePreset(AppMotionPreset.fadeScale, reduced: _reduced);
    _controller = AnimationController(vsync: this, duration: enter.duration);
    final curve = CurvedAnimation(parent: _controller, curve: enter.curve);
    _opacity = curve;
    _scale = Tween<double>(begin: _reduced ? 1 : 0.98, end: 1).animate(curve);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onLayout?.call();
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(scale: _scale, alignment: Alignment.topCenter, child: widget.child),
    );
  }
}
