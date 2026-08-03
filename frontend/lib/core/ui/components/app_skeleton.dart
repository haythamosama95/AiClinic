import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

enum SkeletonVariant { text, circular, rectangular }

/// Shape-matched loading placeholder with calm shimmer (web `Skeleton`).
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    this.variant = SkeletonVariant.rectangular,
    this.width,
    this.height,
    super.key,
  });

  final SkeletonVariant variant;
  final double? width;
  final double? height;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.deliberate,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    if (AppMotion.prefersReducedMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  BorderRadius _borderRadius() {
    return switch (widget.variant) {
      SkeletonVariant.text => BorderRadius.circular(AppRadius.sm),
      SkeletonVariant.circular => BorderRadius.circular(AppRadius.full),
      SkeletonVariant.rectangular => BorderRadius.circular(AppRadius.md),
    };
  }

  double? _effectiveHeight() {
    if (widget.height != null) return widget.height;
    if (widget.variant == SkeletonVariant.text) return 16;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final borderRadius = _borderRadius();
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final effectiveHeight = _effectiveHeight();

    Widget content;
    if (reducedMotion) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: borderRadius,
        ),
      );
    } else {
      content = AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ClipRRect(
            borderRadius: borderRadius,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.isFinite ? constraints.maxWidth : (widget.width ?? 120);
                final height = constraints.maxHeight.isFinite ? constraints.maxHeight : (effectiveHeight ?? 80);
                final sweepWidth = width * 2;

                return Stack(
                  children: [
                    ColoredBox(color: colors.surfaceMuted),
                    Positioned(
                      left: -sweepWidth + (sweepWidth * 2 * _controller.value),
                      top: 0,
                      width: sweepWidth,
                      height: height,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colors.surfaceMuted,
                              colors.surfaceHover,
                              colors.surfaceMuted,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    }

    content = Semantics(
      container: true,
      label: 'Loading',
      liveRegion: true,
      child: content,
    );

    return SizedBox(
      width: widget.width ?? (widget.variant == SkeletonVariant.text ? double.infinity : null),
      height: effectiveHeight,
      child: content,
    );
  }
}
