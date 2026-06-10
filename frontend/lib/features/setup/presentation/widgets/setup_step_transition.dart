import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';

/// Animates slide + fade between wizard steps while the step area height tracks
/// each form's natural size (including validation errors) and resizes smoothly.
class SetupStepTransition extends StatefulWidget {
  const SetupStepTransition({
    required this.step,
    required this.direction,
    required this.organizationStep,
    required this.branchStep,
    required this.staffStep,
    required this.completeStep,
    super.key,
  });

  final SetupWizardStep step;
  final int direction;
  final Widget organizationStep;
  final Widget branchStep;
  final Widget staffStep;
  final Widget completeStep;

  static const duration = Duration(milliseconds: 300);
  static const curve = Curves.easeInOutCubic;

  @override
  State<SetupStepTransition> createState() => _SetupStepTransitionState();
}

class _SetupStepTransitionState extends State<SetupStepTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  SetupWizardStep? _fromStep;
  double? _transitionFromHeight;
  double? _transitionToHeight;
  final _stepKeys = {for (final step in SetupWizardStep.values) step: GlobalKey()};
  final _stepHeights = <SetupWizardStep, double>{};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: SetupStepTransition.duration)
      ..addStatusListener(_onAnimationStatusChanged);
  }

  @override
  void didUpdateWidget(SetupStepTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) {
      _fromStep = oldWidget.step;
      _transitionFromHeight = _heightForStep(oldWidget.step);
      _transitionToHeight = null;
      _controller.reset();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _fromStep == null) {
          return;
        }
        _measureStepHeights();
        final toHeight = _heightForStep(widget.step);
        if (toHeight != null) {
          setState(() => _transitionToHeight = toHeight);
        }
        _controller.forward(from: 0);
      });
    }
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }
    setState(() {
      _fromStep = null;
      _transitionFromHeight = null;
      _transitionToHeight = null;
    });
    _controller.reset();
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onAnimationStatusChanged)
      ..dispose();
    super.dispose();
  }

  Widget _stepWidget(SetupWizardStep step) => switch (step) {
    SetupWizardStep.organization => widget.organizationStep,
    SetupWizardStep.branch => widget.branchStep,
    SetupWizardStep.staff => widget.staffStep,
    SetupWizardStep.complete => widget.completeStep,
  };

  void _scheduleStepHeightMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _measureStepHeights();
    });
  }

  void _measureStepHeights() {
    var changed = false;
    for (final entry in _stepKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        continue;
      }
      final height = box.size.height;
      if (_stepHeights[entry.key] != height) {
        _stepHeights[entry.key] = height;
        changed = true;
      }
    }
    if (changed) {
      setState(() {});
    }
  }

  double? _heightForStep(SetupWizardStep step) {
    final height = _stepHeights[step];
    if (height == null || height <= 0) {
      return null;
    }
    return height;
  }

  double? _animatedTransitionHeight(double progress) {
    final fromStep = _fromStep;
    if (fromStep == null) {
      return null;
    }

    final fromHeight = _transitionFromHeight ?? _heightForStep(fromStep);
    final toHeight = _transitionToHeight ?? _heightForStep(widget.step);
    if (fromHeight == null && toHeight == null) {
      return null;
    }
    if (toHeight == null) {
      return fromHeight;
    }
    if (fromHeight == null) {
      return toHeight;
    }

    return lerpDouble(fromHeight, toHeight, progress);
  }

  Widget _buildStepStack({required bool isAnimating, required Animation<double> animation}) {
    return Stack(
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      children: [
        for (final step in SetupWizardStep.values)
          _buildStepLayerSlot(
            step: step,
            isAnimating: isAnimating,
            animation: animation,
            child: KeyedSubtree(key: _stepKeys[step], child: _stepWidget(step)),
          ),
      ],
    );
  }

  Widget _buildStepLayerSlot({
    required SetupWizardStep step,
    required bool isAnimating,
    required Animation<double> animation,
    required Widget child,
  }) {
    final layer = _SetupStepLayer(
      step: step,
      currentStep: widget.step,
      fromStep: _fromStep,
      isAnimating: isAnimating,
      direction: widget.direction,
      animation: animation,
      child: child,
    );

    if (!isAnimating) {
      return layer;
    }

    final isOutgoing = step == _fromStep;
    final isIncoming = step == widget.step;
    if (!isOutgoing && !isIncoming) {
      return layer;
    }

    return Positioned(top: 0, left: 0, right: 0, child: layer);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleStepHeightMeasure();

    final isAnimating = _fromStep != null;
    final curve = CurvedAnimation(parent: _controller, curve: SetupStepTransition.curve);
    final stack = _buildStepStack(isAnimating: isAnimating, animation: curve);

    if (isAnimating) {
      return AnimatedBuilder(
        animation: curve,
        builder: (context, child) {
          final height = _animatedTransitionHeight(curve.value);
          if (height != null) {
            return ClipRect(
              child: SizedBox(height: height, width: double.infinity, child: child),
            );
          }
          return child!;
        },
        child: stack,
      );
    }

    return AnimatedSize(
      duration: SetupStepTransition.duration,
      curve: SetupStepTransition.curve,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: stack,
    );
  }
}

class _SetupStepLayer extends StatelessWidget {
  const _SetupStepLayer({
    required this.step,
    required this.currentStep,
    required this.fromStep,
    required this.isAnimating,
    required this.direction,
    required this.animation,
    required this.child,
  });

  final SetupWizardStep step;
  final SetupWizardStep currentStep;
  final SetupWizardStep? fromStep;
  final bool isAnimating;
  final int direction;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isCurrent = step == currentStep;
    final isOutgoing = isAnimating && step == fromStep;
    final isIncoming = isAnimating && isCurrent;

    if (!isAnimating && isCurrent) {
      return child;
    }

    if (!isAnimating) {
      return _hiddenLayer(child: child);
    }

    if (isIncoming) {
      return _animatedChild(
        begin: Offset(direction.toDouble(), 0),
        end: Offset.zero,
        opacityBegin: 0,
        opacityEnd: 1,
        child: child,
      );
    }

    if (isOutgoing) {
      return _animatedChild(
        begin: Offset.zero,
        end: Offset(-direction.toDouble(), 0),
        opacityBegin: 1,
        opacityEnd: 0,
        child: child,
      );
    }

    return _hiddenLayer(child: child);
  }

  Widget _hiddenLayer({required Widget child}) {
    return Visibility(
      visible: false,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: false,
      child: IgnorePointer(child: child),
    );
  }

  Widget _animatedChild({
    required Offset begin,
    required Offset end,
    required double opacityBegin,
    required double opacityEnd,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final progress = animation.value;
        return Opacity(
          opacity: opacityBegin + ((opacityEnd - opacityBegin) * progress),
          child: FractionalTranslation(translation: Offset.lerp(begin, end, progress)!, child: child),
        );
      },
      child: child,
    );
  }
}
