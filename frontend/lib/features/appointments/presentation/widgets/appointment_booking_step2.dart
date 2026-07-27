import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:ai_clinic/core/ui/components/app_alert.dart';
import 'package:ai_clinic/core/ui/components/app_booking_day_picker.dart';
import 'package:ai_clinic/core/ui/components/app_booking_slot_grid.dart';
import 'package:ai_clinic/core/ui/components/app_date_picker.dart';
import 'package:ai_clinic/core/ui/components/app_progress.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/models/booking_slot.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_booking_slots.dart';
import 'package:ai_clinic/features/appointments/presentation/formatting/appointment_slot_label.dart';

/// Step 2 of the book-appointment dialog: day and time slot selection.
class AppointmentBookingStep2 extends StatelessWidget {
  const AppointmentBookingStep2({
    required this.patientName,
    required this.branchName,
    required this.preferredDoctorName,
    required this.hasPreferredDoctor,
    required this.today,
    required this.selectedDate,
    required this.selectedSlotStart,
    required this.slots,
    required this.loadingSlots,
    required this.slotMinutes,
    required this.onDateSelected,
    required this.onSlotSelected,
    this.branchAppointmentsError,
    this.dateError,
    this.timeError,
    super.key,
  });

  final String patientName;
  final String branchName;
  final String? preferredDoctorName;
  final bool hasPreferredDoctor;
  final DateTime today;
  final DateTime? selectedDate;
  final DateTime? selectedSlotStart;
  final List<BookingTimeSlot> slots;
  final bool loadingSlots;
  final int slotMinutes;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<BookingTimeSlot> onSlotSelected;
  final String? branchAppointmentsError;
  final String? dateError;
  final String? timeError;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final displaySlots = withAppointmentSlotLabels(slots);
    final openCount = AppointmentBookingSlots.openSlotCount(slots);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _BookingContextBanner(
          colors: colors,
          patientName: patientName,
          branchName: branchName,
          preferredDoctorName: preferredDoctorName,
          today: today,
          selectedDate: selectedDate,
          onDateSelected: onDateSelected,
          dateError: dateError,
          openCount: selectedDate == null ? null : openCount,
        ),
        const SizedBox(height: AppSpacing.space5),
        AppBookingDayPicker(
          key: const Key('appointment_booking_step2_day'),
          today: today,
          selectedDate: selectedDate,
          onDateSelected: onDateSelected,
        ),
        if (selectedDate != null) ...[
          const SizedBox(height: AppSpacing.space5),
          _BookingDaySlotsTransition(
            date: selectedDate!,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_formatFullDate(selectedDate!)} · $slotMinutes-minute slots',
                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                ),
                if (branchAppointmentsError != null) ...[
                  const SizedBox(height: AppSpacing.space3),
                  AppAlert(title: branchAppointmentsError!, variant: AppAlertVariant.danger),
                ],
                const SizedBox(height: AppSpacing.space3),
                if (loadingSlots)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.space8),
                    child: Center(child: AppProgress(variant: ProgressVariant.circular, indeterminate: true)),
                  )
                else
                  IgnorePointer(
                    ignoring: branchAppointmentsError != null,
                    child: AppBookingSlotGrid(
                      slots: displaySlots,
                      selectedStart: selectedSlotStart,
                      hasPreferredDoctor: hasPreferredDoctor,
                      onSlotSelected: onSlotSelected,
                      errorText: timeError,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _formatFullDate(DateTime date) {
    return DateFormat('EEEE, d MMMM y').format(date);
  }
}

/// Directional slide-inline transition when the selected booking day changes.
class _BookingDaySlotsTransition extends StatefulWidget {
  const _BookingDaySlotsTransition({required this.date, required this.child});

  final DateTime date;
  final Widget child;

  @override
  State<_BookingDaySlotsTransition> createState() => _BookingDaySlotsTransitionState();
}

class _BookingDaySlotsTransitionState extends State<_BookingDaySlotsTransition> {
  int _direction = 1;

  @override
  void didUpdateWidget(covariant _BookingDaySlotsTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameDay(oldWidget.date, widget.date)) {
      _direction = widget.date.isAfter(oldWidget.date) ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final duration = AppMotion.resolveDuration(AppMotionPreset.slideInline, reducedMotion: reducedMotion);
    final curve = AppMotion.resolveCurve(AppMotionPreset.slideInline, reducedMotion: reducedMotion);
    final inlineSign = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    final enterOffset = AppMotion.hidden(AppMotionPreset.slideInline).offset.dx * _direction * inlineSign;

    return ClipRect(
      child: AnimatedSize(
        duration: reducedMotion ? Duration.zero : duration,
        curve: curve,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: curve,
          switchOutCurve: AppMotion.inCurve,
          layoutBuilder: (currentChild, previousChildren) => currentChild ?? const SizedBox.shrink(),
          transitionBuilder: (child, animation) {
            return _InlineDayTransition(animation: animation, enterOffset: enterOffset, child: child);
          },
          child: KeyedSubtree(key: ValueKey<String>(_dateKey(widget.date)), child: widget.child),
        ),
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';
}

class _InlineDayTransition extends StatelessWidget {
  const _InlineDayTransition({required this.animation, required this.enterOffset, required this.child});

  final Animation<double> animation;
  final double enterOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        final exiting = animation.status == AnimationStatus.reverse;
        final offset = exiting
            ? Offset.lerp(Offset.zero, Offset(-enterOffset, 0), 1 - t)!
            : Offset.lerp(Offset(enterOffset, 0), Offset.zero, t)!;

        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(offset: offset, child: child),
        );
      },
      child: child,
    );
  }
}

class _BookingContextBanner extends StatelessWidget {
  const _BookingContextBanner({
    required this.colors,
    required this.patientName,
    required this.branchName,
    required this.preferredDoctorName,
    required this.today,
    required this.selectedDate,
    required this.onDateSelected,
    required this.dateError,
    required this.openCount,
  });

  final AppSemanticColors colors;
  final String patientName;
  final String branchName;
  final String? preferredDoctorName;
  final DateTime today;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final String? dateError;
  final int? openCount;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final gradientStart = brightness == Brightness.dark
        ? AppColorPrimitives.teal800.withValues(alpha: 0.25)
        : AppColorPrimitives.teal50.withValues(alpha: 0.4);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderSubtle),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientStart, colors.surfaceDefault],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'BOOKING FOR',
                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary, letterSpacing: 0.4),
                    ),
                    Text(patientName, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
                    Text(
                      '$branchName · ${preferredDoctorName != null ? 'Prefers $preferredDoctorName' : 'Any doctor'}',
                      style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.space4),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text('Date', style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
                        const Spacer(),
                        if (openCount != null)
                          Text(
                            '$openCount open slot${openCount == 1 ? '' : 's'}',
                            style: AppTypography.caption(
                              context,
                            ).copyWith(color: colors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    AppDatePicker(
                      key: const Key('appointment_booking_step2_date'),
                      value: selectedDate,
                      min: today,
                      max: today.add(const Duration(days: 365)),
                      invalid: dateError != null,
                      onChanged: (date) {
                        if (date != null) {
                          onDateSelected(date);
                        }
                      },
                    ),
                    if (dateError != null) ...[
                      const SizedBox(height: AppSpacing.space2),
                      Text(dateError!, style: AppTypography.caption(context).copyWith(color: colors.statusDangerFg)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
