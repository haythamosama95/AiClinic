import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Staggered enter animation for visit section blocks (web `staggerChildren` + `slide-up`).
///
/// The parent state must supply a [TickerProvider] (e.g. via `SingleTickerProviderStateMixin`).
class VisitStagger extends StatefulWidget {
  const VisitStagger({
    required this.vsync,
    required this.children,
    this.stepMs = 40,
    super.key,
  });

  final TickerProvider vsync;
  final int stepMs;
  final List<VisitStaggeredItem> children;

  @override
  State<VisitStagger> createState() => _VisitStaggerState();
}

/// Marks a single child block inside [VisitStagger] for incremental enter motion.
class VisitStaggeredItem extends StatelessWidget {
  const VisitStaggeredItem({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _VisitStaggerState extends State<VisitStagger> {
  late final AnimationController _controller;
  List<CurvedAnimation> _childAnimations = const [];
  var _configured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: widget.vsync, duration: AppMotion.base);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) {
      return;
    }
    _configured = true;
    _configureAnimations();
  }

  void _configureAnimations() {
    _disposeChildAnimations();

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final count = widget.children.length;

    if (count == 0) {
      return;
    }

    final stepDuration = AppMotion.staggerStep(context, stepMs: widget.stepMs);
    final baseDuration = AppMotion.resolveDuration(AppMotionPreset.slideUp, reducedMotion: reducedMotion);
    final totalMs = reducedMotion
        ? 0
        : baseDuration.inMilliseconds + (count - 1) * stepDuration.inMilliseconds;

    _controller.duration = Duration(milliseconds: totalMs);

    if (reducedMotion) {
      _childAnimations = const [];
      _controller.value = 1;
      return;
    }

    _childAnimations = List.generate(count, (index) {
      final beginMs = index * stepDuration.inMilliseconds;
      final endMs = beginMs + baseDuration.inMilliseconds;
      final begin = beginMs / totalMs;
      final end = (endMs / totalMs).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(begin, end, curve: AppMotionEasing.out),
      );
    });

    _controller.forward(from: 0);
  }

  void _disposeChildAnimations() {
    for (final animation in _childAnimations) {
      animation.dispose();
    }
    _childAnimations = const [];
  }

  @override
  void dispose() {
    _disposeChildAnimations();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) {
      return const SizedBox.shrink();
    }

    final reducedMotion = AppMotion.prefersReducedMotion(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.space6,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          _buildStaggeredChild(
            context: context,
            child: widget.children[index].child,
            animation: index < _childAnimations.length
                ? _childAnimations[index]
                : const AlwaysStoppedAnimation<double>(1),
            reducedMotion: reducedMotion,
          ),
      ],
    );
  }

  Widget _buildStaggeredChild({
    required BuildContext context,
    required Widget child,
    required Animation<double> animation,
    required bool reducedMotion,
  }) {
    if (reducedMotion) {
      return child;
    }

    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.slideUp,
      animation: animation,
      child: child,
    );
  }
}
