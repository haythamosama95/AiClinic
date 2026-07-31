import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Animated wait-severity meter for the checked-in panel (web `FlowPulse`).
class QueueFlowPulse extends StatefulWidget {
  const QueueFlowPulse({
    required this.severity,
    required this.patientCount,
    super.key,
  });

  /// 0–1 severity based on max wait time.
  final double severity;

  final int patientCount;

  @override
  State<QueueFlowPulse> createState() => _QueueFlowPulseState();
}

class _QueueFlowPulseState extends State<QueueFlowPulse>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _syncController() {
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final shouldAnimate = tickerEnabled && !disableAnimations;

    if (!shouldAnimate) {
      _controller?.dispose();
      _controller = null;
      return;
    }

    _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }

  Color _severityColor(AppSemanticColors colors) {
    if (widget.severity >= 0.75) {
      return colors.statusDangerFg;
    }
    if (widget.severity >= 0.5) {
      return colors.statusWarningFg;
    }
    return colors.actionPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = _severityColor(colors);
    final fillPercent = widget.severity.clamp(0.08, 1.0);

    return Semantics(
      label: 'Queue wait severity',
      value: '${(widget.severity * 100).round()}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Flow Pulse',
                  style: AppTypography.caption(context).copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: colors.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.patientCount} waiting',
                  style: AppTypography.caption(context).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space1),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: SizedBox(
                height: 4,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: colors.borderDefault),
                    FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: fillPercent,
                      child: _controller == null
                          ? ColoredBox(color: color)
                          : FadeTransition(
                              opacity: Tween<double>(begin: 0.7, end: 1.0)
                                  .animate(_controller!),
                              child: ColoredBox(color: color),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps max wait minutes to a 0–1 severity value (web `waitSeverity`).
double queueFlowPulseSeverity(int maxWaitMinutes) {
  if (maxWaitMinutes <= 10) {
    return 0.2;
  }
  if (maxWaitMinutes <= 20) {
    return 0.45;
  }
  if (maxWaitMinutes <= 30) {
    return 0.7;
  }
  return 0.95;
}
