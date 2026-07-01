import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// A single step in [AppStepper] with a title, optional description, and page.
class AppStepperStep {
  const AppStepperStep({
    required this.title,
    this.description,
    required this.page,
    this.icon,
    this.trailing,
    this.stepKey,
  });

  final String title;
  final String? description;
  final Widget page;
  final IconData? icon;
  final Widget? trailing;
  final Key? stepKey;
}

/// Pill-shaped step rail without page content — for compact pickers or custom layouts.
class AppStepperRail extends StatelessWidget {
  const AppStepperRail({
    required this.steps,
    required this.activeStep,
    this.axis = Axis.vertical,
    this.onStepSelected,
    this.allowStepNavigation = true,
    this.showCard = true,
    super.key,
  });

  final List<AppStepperStep> steps;
  final int activeStep;
  final Axis axis;
  final ValueChanged<int>? onStepSelected;
  final bool allowStepNavigation;
  final bool showCard;

  @override
  Widget build(BuildContext context) {
    return _AppStepperRail(
      steps: steps,
      activeStep: activeStep,
      axis: axis,
      onStepSelected: onStepSelected ?? (_) {},
      allowStepNavigation: allowStepNavigation && onStepSelected != null,
      showCard: showCard,
    );
  }
}

/// Multi-step wizard with a step rail and per-step page content.
///
/// Supports horizontal (rail on top) or vertical (rail on the left) layouts.
/// Steps are freely clickable when [allowStepNavigation] is true.
class AppStepper extends StatefulWidget {
  AppStepper({
    required this.steps,
    this.axis = Axis.horizontal,
    this.initialStep = 0,
    this.currentStep,
    this.onStepChanged,
    this.allowStepNavigation = true,
    this.showCard = true,
    this.pageTransitionDuration = const Duration(milliseconds: 220),
    super.key,
  }) : assert(steps.isNotEmpty, 'AppStepper requires at least one step.');

  final List<AppStepperStep> steps;
  final Axis axis;
  final int initialStep;
  final int? currentStep;
  final ValueChanged<int>? onStepChanged;
  final bool allowStepNavigation;
  final bool showCard;
  final Duration pageTransitionDuration;

  bool get _isControlled => currentStep != null;

  @override
  State<AppStepper> createState() => _AppStepperState();
}

class _AppStepperState extends State<AppStepper> {
  static const _verticalRailWidth = 228.0;

  late int _internalStep;

  int get _activeStep => widget._isControlled ? widget.currentStep! : _internalStep;

  @override
  void initState() {
    super.initState();
    _internalStep = _clampStep(widget.initialStep);
  }

  @override
  void didUpdateWidget(covariant AppStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget._isControlled && oldWidget.initialStep != widget.initialStep) {
      _internalStep = _clampStep(widget.initialStep);
    }
  }

  int _clampStep(int step) => step.clamp(0, widget.steps.length - 1);

  void _selectStep(int index) {
    if (!widget.allowStepNavigation || index == _activeStep) {
      return;
    }

    if (!widget._isControlled) {
      setState(() => _internalStep = index);
    }
    widget.onStepChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.axis == Axis.horizontal;

    final rail = _AppStepperRail(
      steps: widget.steps,
      activeStep: _activeStep,
      axis: widget.axis,
      onStepSelected: _selectStep,
      allowStepNavigation: widget.allowStepNavigation,
      showCard: widget.showCard,
    );

    final content = Expanded(
      child: _AppStepperPageTransition(
        index: _activeStep,
        duration: widget.pageTransitionDuration,
        children: [for (final step in widget.steps) step.page],
      ),
    );

    if (isHorizontal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          rail,
          const SizedBox(height: SpacingTokens.lg),
          content,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _verticalRailWidth, child: rail),
        const SizedBox(width: SpacingTokens.lg),
        content,
      ],
    );
  }
}

class _AppStepperRail extends StatelessWidget {
  const _AppStepperRail({
    required this.steps,
    required this.activeStep,
    required this.axis,
    required this.onStepSelected,
    required this.allowStepNavigation,
    this.showCard = true,
  });

  final List<AppStepperStep> steps;
  final int activeStep;
  final Axis axis;
  final ValueChanged<int> onStepSelected;
  final bool allowStepNavigation;
  final bool showCard;

  static const _markerSize = 36.0;
  static const _connectorThickness = 2.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final shape = context.shapeTokens;
    final theme = Theme.of(context);

    final rail = axis == Axis.horizontal
        ? _HorizontalStepperRail(
            steps: steps,
            activeStep: activeStep,
            onStepSelected: allowStepNavigation ? onStepSelected : null,
            colors: colors,
            theme: theme,
          )
        : _VerticalStepperRail(
            steps: steps,
            activeStep: activeStep,
            onStepSelected: allowStepNavigation ? onStepSelected : null,
            colors: colors,
            theme: theme,
          );

    if (!showCard) {
      return rail;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(shape.xl + SpacingTokens.sm),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg, vertical: SpacingTokens.md),
        child: rail,
      ),
    );
  }

  static _StepVisualState _stepState(int index, int activeStep) {
    if (index < activeStep) {
      return _StepVisualState.completed;
    }
    if (index == activeStep) {
      return _StepVisualState.active;
    }
    return _StepVisualState.inactive;
  }
}

enum _StepVisualState { completed, active, inactive }

class _HorizontalStepperRail extends StatelessWidget {
  const _HorizontalStepperRail({
    required this.steps,
    required this.activeStep,
    required this.onStepSelected,
    required this.colors,
    required this.theme,
  });

  final List<AppStepperStep> steps;
  final int activeStep;
  final ValueChanged<int>? onStepSelected;
  final SemanticColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final shape = context.shapeTokens;
    final markerStyle = _StepMarkerStyle.fromTheme(colors, shape.md + 2);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600);
    final descriptionStyle = theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final columnWidth = trackWidth / steps.length;
        final lineLeft = columnWidth / 2;
        final lineWidth = trackWidth - columnWidth;
        final lineTop = SpacingTokens.sm + _AppStepperRail._markerSize / 2 - _AppStepperRail._connectorThickness / 2;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (steps.length > 1)
              Positioned(
                left: lineLeft,
                top: lineTop,
                width: lineWidth,
                height: _AppStepperRail._connectorThickness,
                child: _AnimatedStepTrack(
                  activeStep: activeStep,
                  stepCount: steps.length,
                  axis: Axis.horizontal,
                  activeColor: colors.primary,
                  inactiveColor: colors.border,
                  thickness: _AppStepperRail._connectorThickness,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < steps.length; i++)
                  Expanded(
                    child: _HorizontalStepCell(
                      key: steps[i].stepKey,
                      step: steps[i],
                      state: _AppStepperRail._stepState(i, activeStep),
                      markerStyle: markerStyle,
                      titleStyle: titleStyle,
                      descriptionStyle: descriptionStyle,
                      onTap: onStepSelected == null ? null : () => onStepSelected!(i),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _HorizontalStepCell extends StatelessWidget {
  const _HorizontalStepCell({
    super.key,
    required this.step,
    required this.state,
    required this.markerStyle,
    required this.titleStyle,
    required this.descriptionStyle,
    this.onTap,
  });

  final AppStepperStep step;
  final _StepVisualState state;
  final _StepMarkerStyle markerStyle;
  final TextStyle? titleStyle;
  final TextStyle? descriptionStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: state == _StepVisualState.active,
      label: step.title,
      child: _StepLabelTapTarget(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StepMarker(state: state, icon: step.icon, style: markerStyle),
                  const SizedBox(width: SpacingTokens.sm),
                  Flexible(
                    child: Text(
                      step.title,
                      style: titleStyle,
                      textAlign: TextAlign.start,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (step.trailing case final trailing?) ...[const SizedBox(width: SpacingTokens.xs), trailing],
                ],
              ),
              if (step.description case final description?) ...[
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  description,
                  style: descriptionStyle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalStepperRail extends StatelessWidget {
  const _VerticalStepperRail({
    required this.steps,
    required this.activeStep,
    required this.onStepSelected,
    required this.colors,
    required this.theme,
  });

  final List<AppStepperStep> steps;
  final int activeStep;
  final ValueChanged<int>? onStepSelected;
  final SemanticColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final shape = context.shapeTokens;
    final markerStyle = _StepMarkerStyle.fromTheme(colors, shape.md + 2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : steps.length * (_AppStepperRail._markerSize + SpacingTokens.lg);
        final labelsWidth = constraints.maxWidth - _AppStepperRail._markerSize - SpacingTokens.sm;
        final rowHeight = trackHeight / steps.length;
        final lineTop = rowHeight / 2;
        final lineHeight = trackHeight - rowHeight;
        final lineLeft = _AppStepperRail._markerSize / 2 - _AppStepperRail._connectorThickness / 2;

        return SizedBox(
          height: trackHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _AppStepperRail._markerSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (steps.length > 1)
                      Positioned(
                        left: lineLeft,
                        top: lineTop,
                        height: lineHeight,
                        width: _AppStepperRail._connectorThickness,
                        child: _AnimatedStepTrack(
                          activeStep: activeStep,
                          stepCount: steps.length,
                          axis: Axis.vertical,
                          activeColor: colors.primary,
                          inactiveColor: colors.border,
                          thickness: _AppStepperRail._connectorThickness,
                        ),
                      ),
                    Column(
                      children: [
                        for (var i = 0; i < steps.length; i++)
                          SizedBox(
                            height: rowHeight,
                            child: Center(
                              child: _StepMarker(
                                key: steps[i].stepKey,
                                state: _AppStepperRail._stepState(i, activeStep),
                                icon: steps[i].icon,
                                onTap: onStepSelected == null ? null : () => onStepSelected!(i),
                                semanticsLabel: steps[i].title,
                                style: markerStyle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              SizedBox(
                width: labelsWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      SizedBox(
                        height: rowHeight,
                        child: _StepLabelTapTarget(
                          onTap: onStepSelected == null ? null : () => onStepSelected!(i),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _StepLabels(
                              step: steps[i],
                              axis: Axis.vertical,
                              titleStyle: theme.textTheme.titleSmall?.copyWith(
                                color: colors.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                              descriptionStyle: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Continuous track from the first to the last step marker with animated fill.
class _AnimatedStepTrack extends StatefulWidget {
  const _AnimatedStepTrack({
    required this.activeStep,
    required this.stepCount,
    required this.axis,
    required this.activeColor,
    required this.inactiveColor,
    required this.thickness,
  });

  final int activeStep;
  final int stepCount;
  final Axis axis;
  final Color activeColor;
  final Color inactiveColor;
  final double thickness;

  static const _duration = Duration(milliseconds: 300);

  @override
  State<_AnimatedStepTrack> createState() => _AnimatedStepTrackState();
}

class _AnimatedStepTrackState extends State<_AnimatedStepTrack> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fillProgress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _AnimatedStepTrack._duration);
    _fillProgress = AlwaysStoppedAnimation(_targetProgress(widget.activeStep, widget.stepCount));
  }

  @override
  void didUpdateWidget(covariant _AnimatedStepTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeStep == oldWidget.activeStep && widget.stepCount == oldWidget.stepCount) {
      return;
    }

    final target = _targetProgress(widget.activeStep, widget.stepCount);
    _fillProgress = Tween<double>(
      begin: _fillProgress.value,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static double _targetProgress(int activeStep, int stepCount) {
    if (stepCount <= 1) {
      return 0;
    }
    return activeStep / (stepCount - 1);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      key: const Key('app_stepper_track'),
      animation: _fillProgress,
      builder: (context, _) {
        final progress = _fillProgress.value.clamp(0.0, 1.0);

        if (widget.axis == Axis.horizontal) {
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              SizedBox(
                width: double.infinity,
                height: widget.thickness,
                child: ColoredBox(color: widget.inactiveColor),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: widget.thickness,
                  child: ColoredBox(color: widget.activeColor),
                ),
              ),
            ],
          );
        }

        return Stack(
          alignment: Alignment.topCenter,
          children: [
            SizedBox(
              width: widget.thickness,
              height: double.infinity,
              child: ColoredBox(color: widget.inactiveColor),
            ),
            FractionallySizedBox(
              heightFactor: progress,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: widget.thickness,
                child: ColoredBox(color: widget.activeColor),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StepLabelTapTarget extends StatelessWidget {
  const _StepLabelTapTarget({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: child),
    );
  }
}

class _StepLabels extends StatelessWidget {
  const _StepLabels({required this.step, required this.axis, required this.titleStyle, required this.descriptionStyle});

  final AppStepperStep step;
  final Axis axis;
  final TextStyle? titleStyle;
  final TextStyle? descriptionStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: axis == Axis.horizontal ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: axis == Axis.horizontal ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                step.title,
                style: titleStyle,
                textAlign: axis == Axis.horizontal ? TextAlign.center : TextAlign.start,
              ),
            ),
            if (step.trailing case final trailing?) ...[const SizedBox(width: SpacingTokens.xs), trailing],
          ],
        ),
        if (step.description case final description?) ...[
          const SizedBox(height: SpacingTokens.xs),
          Text(
            description,
            style: descriptionStyle,
            textAlign: axis == Axis.horizontal ? TextAlign.center : TextAlign.start,
          ),
        ],
      ],
    );
  }
}

class _StepMarkerStyle {
  const _StepMarkerStyle({
    required this.activeColor,
    required this.activeForeground,
    required this.inactiveMarkerColor,
    required this.inactiveBorderColor,
    required this.inactiveIconColor,
    required this.markerRadius,
  });

  final Color activeColor;
  final Color activeForeground;
  final Color inactiveMarkerColor;
  final Color inactiveBorderColor;
  final Color inactiveIconColor;
  final double markerRadius;

  factory _StepMarkerStyle.fromTheme(SemanticColors colors, double markerRadius) {
    return _StepMarkerStyle(
      activeColor: colors.primary,
      activeForeground: colors.primaryForeground,
      inactiveMarkerColor: colors.muted,
      inactiveBorderColor: colors.border,
      inactiveIconColor: colors.mutedForeground,
      markerRadius: markerRadius,
    );
  }
}

class _StepMarker extends StatelessWidget {
  const _StepMarker({super.key, required this.state, required this.style, this.icon, this.onTap, this.semanticsLabel});

  final _StepVisualState state;
  final _StepMarkerStyle style;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  static const _size = _AppStepperRail._markerSize;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = state != _StepVisualState.inactive;

    final marker = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: isHighlighted ? style.activeColor : style.inactiveMarkerColor,
        borderRadius: BorderRadius.circular(style.markerRadius),
        border: isHighlighted ? null : Border.all(color: style.inactiveBorderColor),
        boxShadow: state == _StepVisualState.active
            ? [BoxShadow(color: style.activeColor.withValues(alpha: 0.35), blurRadius: 8, spreadRadius: 2)]
            : null,
      ),
      alignment: Alignment.center,
      child: _markerContent(),
    );

    return Semantics(
      button: onTap != null,
      selected: state == _StepVisualState.active,
      label: semanticsLabel,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: marker),
      ),
    );
  }

  Widget _markerContent() {
    if (state == _StepVisualState.completed) {
      return Icon(Icons.check_rounded, size: 20, color: style.activeForeground);
    }

    if (icon case final stepIcon?) {
      final iconColor = state == _StepVisualState.active
          ? style.activeForeground
          : style.inactiveIconColor.withValues(alpha: 0.85);
      return Icon(stepIcon, size: 20, color: iconColor);
    }

    return switch (state) {
      _StepVisualState.active => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: style.activeForeground, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: style.activeColor, borderRadius: BorderRadius.circular(2)),
        ),
      ),
      _StepVisualState.inactive => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: style.inactiveIconColor.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      _StepVisualState.completed => const SizedBox.shrink(),
    };
  }
}

/// Fades the outgoing page out, swaps content, then fades the incoming page in.
class _AppStepperPageTransition extends StatefulWidget {
  const _AppStepperPageTransition({required this.index, required this.children, required this.duration});

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<_AppStepperPageTransition> createState() => _AppStepperPageTransitionState();
}

class _AppStepperPageTransitionState extends State<_AppStepperPageTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late int _visibleIndex;
  int? _queuedIndex;
  var _isTransitioning = false;

  static const _curve = Curves.easeInOut;

  @override
  void initState() {
    super.initState();
    _visibleIndex = widget.index;
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: _curve);
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant _AppStepperPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.index != _visibleIndex && widget.index != _queuedIndex) {
      _queueTransition(widget.index);
    }
  }

  void _queueTransition(int targetIndex) {
    if (_isTransitioning) {
      _queuedIndex = targetIndex;
      return;
    }
    _runTransition(targetIndex);
  }

  Future<void> _runTransition(int targetIndex) async {
    _isTransitioning = true;
    _queuedIndex = null;

    await _controller.reverse();
    if (!mounted) {
      return;
    }

    setState(() => _visibleIndex = targetIndex);

    await _controller.forward();
    if (!mounted) {
      return;
    }

    _isTransitioning = false;

    final queued = _queuedIndex;
    if (queued != null && queued != _visibleIndex) {
      _queueTransition(queued);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      key: const Key('app_stepper_page_transition'),
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _opacity,
          child: IgnorePointer(ignoring: _isTransitioning, child: child),
        );
      },
      child: IndexedStack(index: _visibleIndex, children: widget.children),
    );
  }
}
