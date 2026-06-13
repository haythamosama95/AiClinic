import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/shadow_tokens.dart';

/// Material container-transform page transition for patient detail routes.
class PatientDetailContainerTransformPage extends CustomTransitionPage<void> {
  PatientDetailContainerTransformPage({required GoRouterState state, required super.child, Rect? sourceRect})
    : super(
        key: state.pageKey,
        transitionDuration: _PatientContainerTransformTransition.duration,
        reverseTransitionDuration: _PatientContainerTransformTransition.duration,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return _PatientContainerTransformTransition(animation: animation, sourceRect: sourceRect, child: child);
        },
      );
}

/// Expands a source rectangle into the destination route with content fade/scale.
class _PatientContainerTransformTransition extends StatefulWidget {
  const _PatientContainerTransformTransition({required this.animation, required this.child, this.sourceRect});

  static const duration = Duration(milliseconds: 300);

  final Animation<double> animation;
  final Rect? sourceRect;
  final Widget child;

  @override
  State<_PatientContainerTransformTransition> createState() => _PatientContainerTransformTransitionState();
}

class _PatientContainerTransformTransitionState extends State<_PatientContainerTransformTransition> {
  static const _curve = Curves.easeInOutCubic;

  Size? _viewportSize;

  bool get _showTransition => widget.animation.value < 1.0 || widget.animation.isAnimating;

  @override
  Widget build(BuildContext context) {
    if (!_showTransition) {
      return widget.child;
    }

    final size = _viewportSize;
    if (size == null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final measured = Size(constraints.maxWidth, constraints.maxHeight);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _viewportSize == measured) {
              return;
            }
            setState(() => _viewportSize = measured);
          });
          return SizedBox(width: measured.width, height: measured.height);
        },
      );
    }

    final curved = CurvedAnimation(parent: widget.animation, curve: _curve, reverseCurve: _curve);

    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (context, child) {
        final t = curved.value;
        final targetRect = Offset.zero & size;
        final renderBox = context.findRenderObject() as RenderBox?;
        final beginRect = _beginRect(widget.sourceRect, renderBox, size, targetRect);
        final rect = Rect.lerp(beginRect, targetRect, t)!;

        final shapes = context.shapeTokens;
        final colors = context.semanticColors;
        final borderRadius = BorderRadius.lerp(BorderRadius.circular(shapes.sm), BorderRadius.circular(shapes.xl), t)!;
        final shadowStrength = lerpDouble(0, 1, t) ?? 0;

        final contentProgress = ((t - 0.12) / 0.88).clamp(0.0, 1.0);
        final contentOpacity = Curves.easeOut.transform(contentProgress);
        final contentScale = 0.94 + (0.06 * contentOpacity);

        final transitionChild = Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            ColoredBox(color: colors.foreground.withValues(alpha: 0.04 * t)),
            Positioned.fromRect(
              rect: rect,
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: borderRadius,
                    border: Border.all(color: colors.border.withValues(alpha: 0.5 + (0.5 * (1 - t)))),
                    boxShadow: [
                      for (final shadow in ShadowTokens.card)
                        BoxShadow(
                          color: shadow.color.withValues(alpha: shadow.color.a * shadowStrength),
                          offset: shadow.offset,
                          blurRadius: shadow.blurRadius * (0.5 + (0.5 * t)),
                          spreadRadius: shadow.spreadRadius,
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxWidth: size.width,
                      maxHeight: size.height,
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: Opacity(
                          opacity: contentOpacity,
                          child: Transform.scale(scale: contentScale, alignment: Alignment.topCenter, child: child),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

        // Semantics are collected after layout; animated flex parent data during
        // the route transition can trip `!semantics.parentDataDirty` assertions.
        return ExcludeSemantics(child: transitionChild);
      },
    );
  }

  Rect _beginRect(Rect? sourceRect, RenderBox? renderBox, Size size, Rect targetRect) {
    if (sourceRect != null && renderBox != null && renderBox.hasSize) {
      final topLeft = renderBox.globalToLocal(sourceRect.topLeft);
      final bottomRight = renderBox.globalToLocal(sourceRect.bottomRight);
      return Rect.fromPoints(topLeft, bottomRight);
    }

    final width = size.width * 0.72;
    final height = size.height * 0.18;
    return Rect.fromCenter(center: targetRect.center, width: width, height: height);
  }
}
