import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/components/app_booking_summary_card.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Acknowledgment step shown after a new appointment is successfully booked.
class AppointmentBookingConfirmedStep extends StatefulWidget {
  const AppointmentBookingConfirmedStep({
    required this.patientName,
    required this.branchName,
    required this.startTime,
    required this.durationMinutes,
    this.doctorName,
    super.key,
  });

  final String patientName;
  final String branchName;
  final DateTime startTime;
  final int durationMinutes;
  final String? doctorName;

  @override
  State<AppointmentBookingConfirmedStep> createState() => _AppointmentBookingConfirmedStepState();
}

class _AppointmentBookingConfirmedStepState extends State<AppointmentBookingConfirmedStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slipController;
  late final Animation<double> _slipScale;
  late final Animation<double> _slipOpacity;

  @override
  void initState() {
    super.initState();
    _slipController = AnimationController(vsync: this, duration: AppMotionDuration.deliberate);
    _slipScale = Tween<double>(
      begin: 0.88,
      end: 1,
    ).animate(CurvedAnimation(parent: _slipController, curve: AppMotion.outCurve));
    _slipOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _slipController,
        curve: const Interval(0.2, 1, curve: AppMotion.outCurve),
      ),
    );
    _slipController.forward();
  }

  @override
  void dispose() {
    _slipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.space2),
          Center(
            child: _AppointmentSlipStamp(
              colors: colors,
              reducedMotion: reducedMotion,
              slipScale: _slipScale,
              slipOpacity: _slipOpacity,
              startTime: widget.startTime,
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          Text(
            'Appointment booked',
            textAlign: TextAlign.center,
            style: AppTypography.h2(context).copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            '${widget.patientName}\'s visit is on the schedule.',
            textAlign: TextAlign.center,
            style: AppTypography.body(context).copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space6),
          AppBookingSummaryCard(
            layout: AppBookingSummaryLayout.grid2,
            items: [
              AppBookingSummaryItem(icon: Icons.person_outline, label: 'Patient', value: widget.patientName),
              AppBookingSummaryItem(icon: Icons.location_on_outlined, label: 'Branch', value: widget.branchName),
              AppBookingSummaryItem(
                icon: Icons.medical_services_outlined,
                label: 'Doctor',
                value: widget.doctorName?.trim().isNotEmpty == true ? widget.doctorName!.trim() : 'Any available',
              ),
              AppBookingSummaryItem(
                icon: Icons.schedule_outlined,
                label: 'Duration',
                value: '${widget.durationMinutes} min',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tear-off calendar slip showing the locked appointment date and time.
class _AppointmentSlipStamp extends StatelessWidget {
  const _AppointmentSlipStamp({
    required this.colors,
    required this.reducedMotion,
    required this.slipScale,
    required this.slipOpacity,
    required this.startTime,
  });

  final AppSemanticColors colors;
  final bool reducedMotion;
  final Animation<double> slipScale;
  final Animation<double> slipOpacity;
  final DateTime startTime;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final headerColor = isDark ? AppColorPrimitives.teal700 : AppColorPrimitives.teal600;
    final bodyColor = isDark ? colors.surfaceDefault : Colors.white;
    final borderColor = isDark ? colors.borderDefault : AppColorPrimitives.teal300.withValues(alpha: 0.45);
    final dayColor = isDark ? colors.textPrimary : AppColorPrimitives.teal800;
    final metaColor = colors.textSecondary;
    final timeColor = isDark ? AppColorPrimitives.teal300 : AppColorPrimitives.teal800;

    final monthLabel = DateFormat('MMM').format(startTime).toUpperCase();
    final dayNumber = DateFormat.d().format(startTime);
    final weekdayLabel = DateFormat('EEEE').format(startTime);
    final startLabel = DateFormat.jm().format(startTime);

    final slip = SizedBox(
      width: 132,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: bodyColor,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: headerColor.withValues(alpha: isDark ? 0.2 : 0.14),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: headerColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg - 1)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
                      child: Text(
                        monthLabel,
                        textAlign: TextAlign.center,
                        style: AppTypography.caption(
                          context,
                        ).copyWith(color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.space3,
                    AppSpacing.space3,
                    AppSpacing.space3,
                    AppSpacing.space4,
                  ),
                  child: Column(
                    children: [
                      Text(
                        dayNumber,
                        style: AppTypography.display(
                          context,
                        ).copyWith(color: dayColor, height: 1, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        weekdayLabel,
                        textAlign: TextAlign.center,
                        style: AppTypography.caption(context).copyWith(color: metaColor),
                      ),
                      const SizedBox(height: AppSpacing.space3),
                      SizedBox(
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isDark ? colors.statusSuccessSurface : AppColorPrimitives.green50,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: colors.statusSuccessBorder),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space2,
                              vertical: AppSpacing.space2,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_available_rounded, size: 16, color: colors.statusSuccessFg),
                                const SizedBox(height: AppSpacing.space1),
                                Text(
                                  startLabel,
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodySm(context).copyWith(
                                    color: timeColor,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [FontFeature.tabularFigures()],
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
              ],
            ),
          ),
          Positioned(
            bottom: -14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.statusSuccessFg,
                shape: BoxShape.circle,
                border: Border.all(color: bodyColor, width: 3),
                boxShadow: [
                  BoxShadow(color: colors.statusSuccessFg.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 1),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.check_rounded, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );

    if (reducedMotion) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.space4),
        child: slip,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space4),
      child: AnimatedBuilder(
        animation: Listenable.merge([slipScale, slipOpacity]),
        builder: (context, child) {
          return Transform.scale(
            scale: slipScale.value,
            child: Opacity(opacity: slipOpacity.value.clamp(0.0, 1.0), child: child),
          );
        },
        child: slip,
      ),
    );
  }
}
