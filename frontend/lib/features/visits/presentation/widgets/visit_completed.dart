import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_recorded_phase_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_stagger.dart';

/// Success screen after a visit is finalized (web `VisitCompleted`).
class VisitCompleted extends StatefulWidget {
  const VisitCompleted({
    required this.patientName,
    required this.finalizedAt,
    required this.onStartNewVisit,
    this.onViewPatient,
    super.key,
  });

  final String patientName;
  final DateTime finalizedAt;
  final VoidCallback onStartNewVisit;
  final VoidCallback? onViewPatient;

  @override
  State<VisitCompleted> createState() => _VisitCompletedState();
}

class _VisitCompletedState extends State<VisitCompleted> with TickerProviderStateMixin {
  late final AnimationController _outerSealController;
  late final AnimationController _innerSealController;
  late final Animation<double> _outerScale;
  late final Animation<double> _outerOpacity;
  late final Animation<double> _innerScale;
  late final Animation<double> _innerRotation;
  var _sealConfigured = false;

  static const _documentedPhases = <({String label, IconData icon})>[
    (label: 'Intake', icon: Icons.assignment_outlined),
    (label: 'Findings', icon: Icons.monitor_heart_outlined),
    (label: 'Treatment', icon: Icons.medication_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _outerSealController = AnimationController(vsync: this);
    _innerSealController = AnimationController(vsync: this);
    _outerScale = Tween<double>(begin: 0.6, end: 1).animate(
      CurvedAnimation(parent: _outerSealController, curve: AppMotionEasing.out),
    );
    _outerOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _outerSealController, curve: AppMotionEasing.out),
    );
    _innerScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _innerSealController, curve: AppMotionEasing.out),
    );
    _innerRotation = Tween<double>(begin: -20 * math.pi / 180, end: 0).animate(
      CurvedAnimation(parent: _innerSealController, curve: AppMotionEasing.out),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sealConfigured) {
      return;
    }
    _sealConfigured = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final sealDuration = AppMotion.resolveDurationFromTokens(
      context: context,
      duration: AppMotionDurationToken.deliberate,
      ease: AppMotionEasingToken.out,
    );

    _outerSealController.duration = sealDuration;
    _innerSealController.duration = sealDuration;

    if (reducedMotion) {
      _outerSealController.value = 1;
      _innerSealController.value = 1;
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _outerSealController.forward(from: 0);
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _innerSealController.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _outerSealController.dispose();
    _innerSealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final locale = Localizations.localeOf(context).toString();
    final formattedAt = DateFormat.yMMMEd(locale).add_jm().format(widget.finalizedAt.toLocal());
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 576),
        child: VisitStagger(
          vsync: this,
          stepMs: 70,
          children: [
            VisitStaggeredItem(
              child: AppCard(
                variant: CardVariant.raised,
                padding: CardPadding.lg,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment.topCenter,
                              radius: 0.9,
                              colors: [
                                colors.statusSuccessSurface.withValues(alpha: 0.6),
                                Colors.transparent,
                              ],
                              stops: const [0, 0.7],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.space6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _AnimatedSeal(
                              colors: colors,
                              outerScale: reducedMotion ? const AlwaysStoppedAnimation(1) : _outerScale,
                              outerOpacity: reducedMotion ? const AlwaysStoppedAnimation(1) : _outerOpacity,
                              innerScale: reducedMotion ? const AlwaysStoppedAnimation(1) : _innerScale,
                              innerRotation: reducedMotion ? const AlwaysStoppedAnimation(0) : _innerRotation,
                            ),
                            const SizedBox(height: AppSpacing.space6),
                            Text(
                              'Visit completed',
                              style: AppTypography.h1(context),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.space2),
                            Text.rich(
                              TextSpan(
                                style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                                children: [
                                  const TextSpan(text: 'Documentation for '),
                                  TextSpan(
                                    text: widget.patientName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  const TextSpan(
                                    text: ' is on record and available in the patient chart.',
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.space2),
                            Text(
                              formattedAt,
                              style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary),
                            ),
                            const SizedBox(height: AppSpacing.space8),
                            Semantics(
                              label: 'Documented phases',
                              child: Row(
                                children: [
                                  for (var index = 0; index < _documentedPhases.length; index++) ...[
                                    if (index > 0) const SizedBox(width: AppSpacing.space2),
                                    Expanded(
                                      child: _StaggeredRecordedPhase(
                                        vsync: this,
                                        label: _documentedPhases[index].label,
                                        icon: _documentedPhases[index].icon,
                                        delay: Duration(milliseconds: 150 + index * 60),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space8),
                            _ActionButtons(
                              onViewPatient: widget.onViewPatient,
                              onStartNewVisit: widget.onStartNewVisit,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedSeal extends StatelessWidget {
  const _AnimatedSeal({
    required this.colors,
    required this.outerScale,
    required this.outerOpacity,
    required this.innerScale,
    required this.innerRotation,
  });

  final AppSemanticColors colors;
  final Animation<double> outerScale;
  final Animation<double> outerOpacity;
  final Animation<double> innerScale;
  final Animation<double> innerRotation;

  static const _sealSize = 80.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([outerScale, outerOpacity, innerScale, innerRotation]),
      builder: (context, child) {
        return Opacity(
          opacity: outerOpacity.value,
          child: Transform.scale(
            scale: outerScale.value,
            child: SizedBox(
              width: _sealSize,
              height: _sealSize,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Transform.scale(
                    scale: 1.25,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.statusSuccessSurface.withValues(alpha: 0.7),
                        ),
                        child: const SizedBox(width: _sealSize, height: _sealSize),
                      ),
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.statusSuccessSurface,
                        border: Border.all(color: colors.statusSuccessBorder, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: colors.surfaceRaised,
                            spreadRadius: 6,
                          ),
                          BoxShadow(
                            color: colors.statusSuccessSurface,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: _sealSize,
                        height: _sealSize,
                        child: Center(
                          child: Transform.rotate(
                            angle: innerRotation.value,
                            child: Transform.scale(
                              scale: innerScale.value,
                              child: Icon(
                                Icons.check_rounded,
                                size: 36,
                                color: colors.statusSuccessFg,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StaggeredRecordedPhase extends StatefulWidget {
  const _StaggeredRecordedPhase({
    required this.vsync,
    required this.label,
    required this.icon,
    required this.delay,
  });

  final TickerProvider vsync;
  final String label;
  final IconData icon;
  final Duration delay;

  @override
  State<_StaggeredRecordedPhase> createState() => _StaggeredRecordedPhaseState();
}

class _StaggeredRecordedPhaseState extends State<_StaggeredRecordedPhase> {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  var _configured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: widget.vsync, duration: AppMotion.base);
    _animation = CurvedAnimation(parent: _controller, curve: AppMotionEasing.out);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) {
      return;
    }
    _configured = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    if (reducedMotion) {
      _controller.value = 1;
      return;
    }

    Future<void>.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = VisitRecordedPhaseCard(label: widget.label, icon: widget.icon);
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    if (reducedMotion) {
      return card;
    }

    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.slideUp,
      animation: _animation,
      child: card,
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.onStartNewVisit,
    this.onViewPatient,
  });

  final VoidCallback onStartNewVisit;
  final VoidCallback? onViewPatient;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Wrap(
        spacing: AppSpacing.space2,
        runSpacing: AppSpacing.space2,
        alignment: WrapAlignment.center,
        children: [
          if (onViewPatient != null)
            AppButton(
              variant: AppButtonVariant.secondary,
              leadingIcon: const Icon(Icons.person_outline_rounded, size: 16),
              onPressed: onViewPatient,
              child: const Text('View patient record'),
            ),
          AppButton(
            variant: AppButtonVariant.secondary,
            leadingIcon: const Icon(Icons.print_outlined, size: 16),
            onPressed: () {},
            child: const Text('Print summary'),
          ),
          AppButton(
            variant: AppButtonVariant.primary,
            trailingIcon: const Icon(Icons.arrow_forward_rounded, size: 16),
            onPressed: onStartNewVisit,
            child: const Text('Start new visit'),
          ),
        ],
      ),
    );
  }
}
