import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';

/// Shared list shell — one recessed board, flat rows inside.
class QueueFlowList extends StatelessWidget {
  const QueueFlowList({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.lg), child: child),
    );
  }
}

/// Instrument readout for wait duration — the queue board's signature element.
class QueueWaitDial extends StatelessWidget {
  const QueueWaitDial({required this.wait, required this.tier, super.key});

  final Duration wait;
  final AppointmentQueueWaitTier tier;

  static const width = 52.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (value, unit) = _dialParts(wait);

    final foreground = switch (tier) {
      AppointmentQueueWaitTier.critical => colors.statusDangerFg,
      AppointmentQueueWaitTier.warning => colors.statusWarningFg,
      AppointmentQueueWaitTier.normal => colors.textPrimary,
    };

    final background = switch (tier) {
      AppointmentQueueWaitTier.critical => colors.statusDangerSurface.withValues(alpha: 0.55),
      AppointmentQueueWaitTier.warning => colors.statusWarningSurface.withValues(alpha: 0.45),
      AppointmentQueueWaitTier.normal => colors.surfaceDefault,
    };

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: switch (tier) {
              AppointmentQueueWaitTier.critical => colors.statusDangerBorder.withValues(alpha: 0.4),
              AppointmentQueueWaitTier.warning => colors.statusWarningBorder.withValues(alpha: 0.35),
              AppointmentQueueWaitTier.normal => colors.borderDefault,
            },
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: AppTypography.mono(context).copyWith(
                  fontSize: tier == AppointmentQueueWaitTier.critical ? 17 : 15,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: foreground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (unit != null) ...[
                const SizedBox(height: 2),
                Text(
                  unit,
                  style: AppTypography.caption(context).copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: foreground.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (String value, String? unit) _dialParts(Duration duration) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes < 60) {
      return ('$totalMinutes', 'min');
    }
    final hours = duration.inHours;
    final minutes = totalMinutes % 60;
    if (minutes == 0) {
      return ('${hours}h', null);
    }
    return ('${hours}h', '${minutes}m');
  }
}

/// Checked-in patient row for the waiting panel.
class QueueWaitingPatientRow extends StatelessWidget {
  const QueueWaitingPatientRow({
    required this.patientName,
    required this.queuePosition,
    required this.wait,
    required this.tier,
    required this.appointmentTimeLabel,
    this.arrivalTimeLabel,
    super.key,
  });

  final String patientName;
  final int queuePosition;
  final Duration wait;
  final AppointmentQueueWaitTier tier;
  final String appointmentTimeLabel;
  final String? arrivalTimeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheduleLabel = arrivalTimeLabel != null ? '$appointmentTimeLabel · $arrivalTimeLabel' : appointmentTimeLabel;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.space3,
        AppSpacing.space3,
        AppSpacing.space3,
        AppSpacing.space3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QueueWaitDial(wait: wait, tier: tier),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySm(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary),
                      ),
                    ),
                    Text(
                      '#$queuePosition',
                      style: AppTypography.mono(context).copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colors.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  scheduleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(context).copyWith(color: colors.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Throughput readout for doctors — mirrors [QueueWaitDial] layout.
class QueueDoctorLoadDial extends StatelessWidget {
  const QueueDoctorLoadDial({required this.patientsSeenToday, required this.isAvailable, super.key});

  final int patientsSeenToday;
  final bool isAvailable;

  static const width = QueueWaitDial.width;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final foreground = isAvailable ? colors.statusSuccessFg : colors.statusInfoFg;
    final background = isAvailable
        ? colors.statusSuccessSurface.withValues(alpha: 0.45)
        : colors.statusInfoSurface.withValues(alpha: 0.45);

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isAvailable
                ? colors.statusSuccessBorder.withValues(alpha: 0.35)
                : colors.statusInfoBorder.withValues(alpha: 0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$patientsSeenToday',
                style: AppTypography.mono(context).copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: foreground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'seen',
                style: AppTypography.caption(context).copyWith(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: foreground.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Doctor-on-shift row for the doctors panel.
class QueueDoctorShiftRow extends StatelessWidget {
  const QueueDoctorShiftRow({
    required this.doctorName,
    required this.isAvailable,
    required this.patientsSeenToday,
    this.currentPatientName,
    this.idleLabel,
    this.lagMinutes,
    super.key,
  });

  final String doctorName;
  final bool isAvailable;
  final int patientsSeenToday;
  final String? currentPatientName;
  final String? idleLabel;
  final int? lagMinutes;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final statusLabel = isAvailable ? 'Available' : 'With patient';
    final statusColor = isAvailable ? colors.statusSuccessFg : colors.statusInfoFg;

    final detailParts = <String>[];
    if (!isAvailable && currentPatientName != null) {
      detailParts.add(currentPatientName!);
    } else if (idleLabel != null) {
      detailParts.add(idleLabel!);
    }
    if (lagMinutes != null && lagMinutes! >= 15) {
      detailParts.add('+$lagMinutes min behind');
    }
    final detailLabel = detailParts.join(' · ');

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.space3,
        AppSpacing.space3,
        AppSpacing.space3,
        AppSpacing.space3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QueueDoctorLoadDial(patientsSeenToday: patientsSeenToday, isAvailable: isAvailable),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        doctorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySm(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary),
                      ),
                    ),
                    Text(
                      statusLabel,
                      style: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600, color: statusColor),
                    ),
                  ],
                ),
                if (detailLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detailLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context).copyWith(
                      color: lagMinutes != null && lagMinutes! >= 15 && isAvailable
                          ? colors.statusWarningFg
                          : colors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
