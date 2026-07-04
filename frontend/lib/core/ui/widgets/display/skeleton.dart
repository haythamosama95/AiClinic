import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/providers/reduced_motion_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

enum AppSkeletonShape { text, rect, circle }

/// Shape-matched loading placeholder with calm shimmer animation.
class AppSkeleton extends ConsumerStatefulWidget {
  const AppSkeleton({
    super.key,
    this.shape = AppSkeletonShape.rect,
    this.width,
    this.height,
  });

  final AppSkeletonShape shape;
  final double? width;
  final double? height;

  @override
  ConsumerState<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends ConsumerState<AppSkeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  bool _reducedMotion(BuildContext context) {
    return ref.watch(reducedMotionProvider) ||
        AppMotion.isReducedMotion(context);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.deliberate,
    )..repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  BorderRadius get _borderRadius => switch (widget.shape) {
    AppSkeletonShape.text => AppRadius.smAll,
    AppSkeletonShape.rect => AppRadius.mdAll,
    AppSkeletonShape.circle => AppRadius.fullAll,
  };

  double? get _width => switch (widget.shape) {
    AppSkeletonShape.circle => widget.width ?? widget.height ?? 40,
    _ => widget.width,
  };

  double get _height => switch (widget.shape) {
    AppSkeletonShape.text => widget.height ?? 16,
    AppSkeletonShape.circle => widget.height ?? widget.width ?? 40,
    AppSkeletonShape.rect => widget.height ?? 48,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduced = _reducedMotion(context);
    final width = _width;
    final height = _height;

    final decoration = BoxDecoration(
      borderRadius: _borderRadius,
      color: colors.surfaceMuted,
    );

    Widget child = Container(
      width: width,
      height: height,
      decoration: decoration,
    );

    if (!reduced && _controller != null) {
      child = AnimatedBuilder(
        animation: _controller!,
        builder: (context, child) {
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: _borderRadius,
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  colors.surfaceMuted,
                  colors.surfaceHover,
                  colors.surfaceMuted,
                ],
                stops: const [0, 0.5, 1],
                transform: _SlideGradientTransform(_controller!.value),
              ),
            ),
            child: SizedBox(width: width, height: height),
          );
        },
      );
    }

    return Semantics(label: 'Loading', container: true, child: child);
  }
}

class _SlideGradientTransform extends GradientTransform {
  const _SlideGradientTransform(this.slidePercent);

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 1),
      0,
      0,
    );
  }
}
