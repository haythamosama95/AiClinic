import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Responsive record-card grid with staggered enter motion (web `RecordCardGrid`).
class PatientRecordGrid extends StatelessWidget {
  const PatientRecordGrid({required this.children, this.mainAxisExtent = 196, this.maxCrossAxisCount = 3, super.key});

  final List<Widget> children;

  /// Fixed row height per grid cell. When null, each card sizes to its content.
  final double? mainAxisExtent;

  /// Maximum columns at the widest breakpoint (default 3; visits use 4).
  final int maxCrossAxisCount;

  static const _smBreakpoint = 640.0;
  static const _xlBreakpoint = 1280.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = switch (constraints.maxWidth) {
          < _smBreakpoint => 1,
          < _xlBreakpoint => 2,
          _ => maxCrossAxisCount,
        };

        if (mainAxisExtent == null) {
          final gap = AppSpacing.space4;
          final itemWidth = (constraints.maxWidth - gap * (crossAxisCount - 1)) / crossAxisCount;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var index = 0; index < children.length; index++)
                SizedBox(
                  width: itemWidth,
                  child: _StaggeredGridChild(index: index, child: children[index]),
                ),
            ],
          );
        }

        return GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: AppSpacing.space4,
          crossAxisSpacing: AppSpacing.space4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisExtent: mainAxisExtent!,
          children: [
            for (var index = 0; index < children.length; index++)
              _StaggeredGridChild(index: index, child: children[index]),
          ],
        );
      },
    );
  }
}

class _StaggeredGridChild extends StatefulWidget {
  const _StaggeredGridChild({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggeredGridChild> createState() => _StaggeredGridChildState();
}

class _StaggeredGridChildState extends State<_StaggeredGridChild> with SingleTickerProviderStateMixin {
  static const _staggerStepMs = 45;
  static const _maxStaggerMs = 270;

  late final AnimationController _controller;
  CurvedAnimation? _animation;
  var _configured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) {
      return;
    }
    _configured = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    _controller.duration = AppMotion.resolveDuration(AppMotionPreset.rowEnter, reducedMotion: reducedMotion);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.resolveCurve(AppMotionPreset.rowEnter, reducedMotion: reducedMotion),
    );

    final delay = reducedMotion
        ? Duration.zero
        : Duration(milliseconds: (widget.index * _staggerStepMs).clamp(0, _maxStaggerMs));

    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _animation?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.rowEnter,
      animation: _animation ?? _controller,
      child: widget.child,
    );
  }
}
