import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_layout.dart';

/// Keeps every wizard step laid out (tallest step sets height) while animating
/// slide + fade transitions between the active step and the previous one.
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

  @override
  State<SetupStepTransition> createState() => _SetupStepTransitionState();
}

class _SetupStepTransitionState extends State<SetupStepTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  SetupWizardStep? _fromStep;
  final _stackKey = GlobalKey();
  final _stepKeys = {for (final step in SetupWizardStep.values) step: GlobalKey()};
  double? _stepAreaHeight;
  var _measureFrames = 0;
  double _lastMeasuredMax = 0;
  var _stableMeasureFrames = 0;

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
      _controller.forward(from: 0);
    }
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }
    setState(() => _fromStep = null);
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

  void _reportRequiredHeight(double height) {
    if (!mounted || height <= 0) {
      return;
    }
    if (height > (_stepAreaHeight ?? 0)) {
      setState(() => _stepAreaHeight = height);
    }
  }

  void _scheduleStepAreaHeightSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stepAreaHeight != null) {
        return;
      }

      _measureFrames++;

      var maxHeight = _stackKey.currentContext?.size?.height ?? 0;
      var allMeasured = true;
      for (final key in _stepKeys.values) {
        final height = key.currentContext?.size?.height ?? 0;
        if (height <= 0) {
          allMeasured = false;
        }
        maxHeight = math.max(maxHeight, height);
      }
      if (maxHeight <= 0) {
        return;
      }

      if (!allMeasured && _measureFrames < 12) {
        return;
      }

      if (maxHeight == _lastMeasuredMax) {
        _stableMeasureFrames++;
      } else {
        _lastMeasuredMax = maxHeight;
        _stableMeasureFrames = 0;
      }

      if (_stableMeasureFrames < 2 && _measureFrames < 12) {
        return;
      }

      setState(() => _stepAreaHeight = maxHeight);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleStepAreaHeightSync();

    final isAnimating = _fromStep != null;
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
    final fillHeight = _stepAreaHeight != null;

    final stack = Stack(
      key: _stackKey,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      children: [
        for (final step in SetupWizardStep.values)
          _layerSlot(
            fillHeight: fillHeight,
            child: KeyedSubtree(
              key: _stepKeys[step],
              child: _SetupStepLayer(
                step: step,
                currentStep: widget.step,
                fromStep: _fromStep,
                isAnimating: isAnimating,
                direction: widget.direction,
                animation: curve,
                child: _stepWidget(step),
              ),
            ),
          ),
      ],
    );

    final clipped = ClipRect(child: stack);

    if (!fillHeight) {
      return clipped;
    }

    return SetupStepHeightScope(
      onRequiredHeight: _reportRequiredHeight,
      child: SetupStepFillScope(
        fillHeight: true,
        child: SizedBox(height: _stepAreaHeight, child: clipped),
      ),
    );
  }

  Widget _layerSlot({required bool fillHeight, required Widget child}) {
    if (!fillHeight) {
      return child;
    }
    return Positioned(top: 0, left: 0, right: 0, bottom: 0, child: child);
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
      return _maintainSizeLayer(visible: true, ignoringPointers: false, child: child);
    }

    if (!isAnimating) {
      return _maintainSizeLayer(visible: false, ignoringPointers: true, child: child);
    }

    if (isIncoming) {
      return _maintainSizeLayer(
        visible: true,
        ignoringPointers: true,
        child: _animatedChild(
          begin: Offset(direction.toDouble(), 0),
          end: Offset.zero,
          opacityBegin: 0,
          opacityEnd: 1,
          child: child,
        ),
      );
    }

    if (isOutgoing) {
      return _maintainSizeLayer(
        visible: true,
        ignoringPointers: true,
        child: _animatedChild(
          begin: Offset.zero,
          end: Offset(-direction.toDouble(), 0),
          opacityBegin: 1,
          opacityEnd: 0,
          child: child,
        ),
      );
    }

    return _maintainSizeLayer(visible: false, ignoringPointers: true, child: child);
  }

  Widget _maintainSizeLayer({required bool visible, required bool ignoringPointers, required Widget child}) {
    return Visibility(
      visible: visible,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: IgnorePointer(ignoring: ignoringPointers, child: child),
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
