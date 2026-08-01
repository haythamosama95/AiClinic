import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// Animated fullscreen overlay that expands from [sourceRect] to the viewport.
class AppointmentCalendarFullscreenOverlay extends StatefulWidget {
  const AppointmentCalendarFullscreenOverlay({
    required this.sourceRect,
    required this.onClose,
    required this.child,
    this.onReady,
    super.key,
  });

  final Rect sourceRect;
  final VoidCallback onClose;
  final Widget child;
  final ValueChanged<Future<void> Function()>? onReady;

  @override
  State<AppointmentCalendarFullscreenOverlay> createState() =>
      AppointmentCalendarFullscreenOverlayState();
}

class AppointmentCalendarFullscreenOverlayState
    extends State<AppointmentCalendarFullscreenOverlay>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  var _isClosing = false;
  var _didInitController = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitController) {
      return;
    }
    _didInitController = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    _controller = AnimationController(
      vsync: this,
      duration: reducedMotion ? Duration.zero : AppMotion.slow,
      reverseDuration: reducedMotion ? Duration.zero : AppMotion.base,
    )..forward();
    widget.onReady?.call(close);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    final controller = _controller;
    if (controller != null) {
      await controller.reverse();
    }
    if (mounted) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final viewport = MediaQuery.sizeOf(context);
    final targetRect = Offset.zero & viewport;
    final radiusLg = AppRadius.lg;
    final controller = _controller;

    if (controller == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = AppMotion.outCurve.transform(controller.value);
        final rect = Rect.lerp(widget.sourceRect, targetRect, t)!;
        final radius = lerpDouble(radiusLg, 0, t)!;
        final scrimOpacity = lerpDouble(0, 0.42, t)!;

        return Stack(
          fit: StackFit.expand,
          children: [
            ModalBarrier(
              dismissible: false,
              color: colors.surfaceCanvas.withValues(alpha: scrimOpacity),
            ),
            Positioned.fromRect(
              rect: rect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Material(color: colors.surfaceCanvas, child: child),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// Global rect of [context]'s render box in screen coordinates.
Rect? globalRectOnScreen(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return null;
  }
  final topLeft = box.localToGlobal(Offset.zero);
  return topLeft & box.size;
}
