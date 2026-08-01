import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/theme_transition_controller.dart';

/// Hosts a circular reveal when switching between light and dark themes.
///
/// Mirrors the web View Transitions API pattern: capture the current frame,
/// apply the new theme, then peel away the old snapshot through an expanding
/// circle from the user's click point.
class ThemeTransitionHost extends ConsumerStatefulWidget {
  const ThemeTransitionHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ThemeTransitionHost> createState() => _ThemeTransitionHostState();
}

class _ThemeTransitionHostState extends ConsumerState<ThemeTransitionHost> with SingleTickerProviderStateMixin {
  final _repaintKey = GlobalKey();
  late final ThemeTransitionRegistry _registry;

  late final AnimationController _controller;
  OverlayEntry? _overlayEntry;
  ui.Image? _snapshot;
  Offset? _origin;
  double _maxRadius = 0;
  var _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _registry = ref.read(themeTransitionRegistryProvider);
    _registry.runner = _runTransition;
    _controller = AnimationController(vsync: this, duration: AppMotion.deliberate)
      ..addListener(() => _overlayEntry?.markNeedsBuild());
  }

  @override
  void dispose() {
    if (identical(_registry.runner, _runTransition)) {
      _registry.runner = null;
    }
    _controller.dispose();
    _overlayEntry?.remove();
    _snapshot?.dispose();
    super.dispose();
  }

  Future<void> _runTransition(ThemeMode target, Offset origin) async {
    if (!mounted || _isAnimating) {
      return;
    }

    final boundary = _repaintKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      setAppThemeMode(ref, target);
      return;
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    ui.Image image;
    try {
      image = await boundary.toImage(pixelRatio: pixelRatio);
    } catch (_) {
      if (mounted) {
        setAppThemeMode(ref, target);
      }
      return;
    }

    if (!mounted) {
      image.dispose();
      return;
    }

    final viewport = MediaQuery.sizeOf(context);
    _origin = origin;
    _maxRadius = themeRevealMaxRadius(origin, viewport);
    _snapshot = image;

    setAppThemeMode(ref, target);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      image.dispose();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final snapshot = _snapshot;
        final center = _origin;
        if (snapshot == null || center == null) {
          return const SizedBox.shrink();
        }

        final radius = _maxRadius * AppMotion.inOutCurve.transform(_controller.value);
        return Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ThemeRevealPainter(image: snapshot, center: center, radius: radius),
            ),
          ),
        );
      },
    );

    final overlay = ref.read(rootNavigatorKeyProvider).currentState?.overlay;
    if (overlay == null) {
      _overlayEntry = null;
      _snapshot?.dispose();
      _snapshot = null;
      _origin = null;
      return;
    }

    overlay.insert(_overlayEntry!);
    _isAnimating = true;

    try {
      _controller.reset();
      await _controller.forward();
    } finally {
      _overlayEntry?.remove();
      _overlayEntry = null;
      _snapshot?.dispose();
      _snapshot = null;
      _origin = null;
      _isAnimating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: _repaintKey, child: widget.child);
  }
}

class _ThemeRevealPainter extends CustomPainter {
  const _ThemeRevealPainter({required this.image, required this.center, required this.radius});

  final ui.Image image;
  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = Path()..addRect(Offset.zero & size);
    final hole = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas
      ..clipPath(Path.combine(PathOperation.difference, viewport, hole))
      ..drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint(),
      );
  }

  @override
  bool shouldRepaint(covariant _ThemeRevealPainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.center != center || oldDelegate.radius != radius;
  }
}
