import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/features/appointments/presentation/utils/appointment_presentation_formatting.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

/// Confirmed move times returned from [showAppointmentRescheduleConfirmDialog].
class AppointmentRescheduleConfirmResult {
  const AppointmentRescheduleConfirmResult({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// Confirms a calendar drag reschedule after client-side validation passes.
Future<AppointmentRescheduleConfirmResult?> showAppointmentRescheduleConfirmDialog(
  BuildContext context, {
  required AppointmentListItem appointment,
  required DateTime newStart,
  required DateTime newEnd,
  required BranchWorkingSchedule schedule,
  required List<AppointmentListItem> branchAppointments,
}) {
  return showAppDialog<AppointmentRescheduleConfirmResult>(
    context,
    size: AppDialogSize.md,
    barrierDismissible: false,
    semanticLabel: 'Move appointment',
    builder: (dialogContext, close) {
      return _AppointmentRescheduleConfirmDialogContent(
        appointment: appointment,
        newStart: newStart,
        newEnd: newEnd,
        schedule: schedule,
        branchAppointments: branchAppointments,
        onClose: () => close(),
        onConfirm: (result) => close(result),
      );
    },
  );
}

class _AppointmentRescheduleConfirmDialogContent extends StatefulWidget {
  const _AppointmentRescheduleConfirmDialogContent({
    required this.appointment,
    required this.newStart,
    required this.newEnd,
    required this.schedule,
    required this.branchAppointments,
    required this.onClose,
    required this.onConfirm,
  });

  final AppointmentListItem appointment;
  final DateTime newStart;
  final DateTime newEnd;
  final BranchWorkingSchedule schedule;
  final List<AppointmentListItem> branchAppointments;
  final VoidCallback onClose;
  final ValueChanged<AppointmentRescheduleConfirmResult> onConfirm;

  @override
  State<_AppointmentRescheduleConfirmDialogContent> createState() =>
      _AppointmentRescheduleConfirmDialogContentState();
}

class _AppointmentRescheduleConfirmDialogContentState extends State<_AppointmentRescheduleConfirmDialogContent> {
  late DateTime _startTime;
  late DateTime _endTime;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _startTime = widget.newStart.toLocal();
    _endTime = widget.newEnd.toLocal();
    _validationError = _validateTimes();
  }

  DateTime _combineDateAndTime(DateTime date, String timeValue) {
    final parts = timeValue.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  int get _durationMinutes => _endTime.difference(_startTime).inMinutes;

  void _setStartTime(DateTime value) {
    setState(() {
      _startTime = value;
      if (!_endTime.isAfter(_startTime)) {
        final originalDuration = widget.appointment.endTime.difference(widget.appointment.startTime).inMinutes;
        _endTime = _startTime.add(Duration(minutes: originalDuration.clamp(5, 9999)));
      }
      _validationError = _validateTimes();
    });
  }

  void _setEndTime(DateTime value) {
    setState(() {
      _endTime = value;
      _validationError = _validateTimes();
    });
  }

  String? _validateTimes() {
    if (!_endTime.isAfter(_startTime)) {
      return 'End time must be after start time.';
    }

    return AppointmentRescheduleValidation.validateMove(
      appointment: widget.appointment,
      newStart: _startTime,
      newEnd: _endTime,
      schedule: widget.schedule,
      branchAppointments: widget.branchAppointments,
    );
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;
    final today = DateTime(clock.now().year, clock.now().month, clock.now().day);
    final canMove = _validationError == null;

    return AppDialog(
      title: 'Move appointment?',
      onClose: widget.onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.appointment.patientName, style: typography.title),
          const SizedBox(height: AppSpacing.s3),
          Text('From', style: typography.caption.copyWith(color: colors.textTertiary)),
          Text(
            '${AppointmentPresentationFormatting.formatDate(widget.appointment.startTime)} · '
            '${AppointmentPresentationFormatting.formatTimeRange(widget.appointment.startTime, widget.appointment.endTime)}',
            style: typography.body,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text('To', style: typography.caption.copyWith(color: colors.textTertiary)),
          const SizedBox(height: AppSpacing.s2),
          AppFormField(
            label: 'Date',
            child: AppDatePicker(
              key: const Key('appointment_reschedule_pick_date'),
              value: DateTime(_startTime.year, _startTime.month, _startTime.day),
              min: today,
              max: today.add(const Duration(days: 365)),
              onChanged: (date) {
                if (date == null) {
                  return;
                }
                _setStartTime(_combineDateAndTime(date, AppointmentPresentationFormatting.formatTime(_startTime)));
                _setEndTime(_combineDateAndTime(date, AppointmentPresentationFormatting.formatTime(_endTime)));
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppFormField(
                  label: 'Start time',
                  child: AppTimePicker(
                    key: const Key('appointment_reschedule_pick_start'),
                    value: AppointmentPresentationFormatting.formatTime(_startTime),
                    onChanged: (time) {
                      _setStartTime(_combineDateAndTime(_startTime, time));
                    },
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: AppFormField(
                  label: 'End time',
                  child: AppTimePicker(
                    key: const Key('appointment_reschedule_pick_end'),
                    value: AppointmentPresentationFormatting.formatTime(_endTime),
                    onChanged: (time) {
                      _setEndTime(_combineDateAndTime(_endTime, time));
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'Duration: $_durationMinutes min',
            style: typography.caption.copyWith(color: colors.textTertiary),
          ),
          if (_validationError != null) ...[
            const SizedBox(height: AppSpacing.s3),
            Text(_validationError!, style: typography.caption.copyWith(color: colors.statusDangerFg)),
          ],
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: widget.onClose,
          ),
          const SizedBox(width: AppSpacing.s2),
          AppButton(
            key: const Key('appointment_reschedule_confirm'),
            label: 'Move',
            onPressed: canMove
                ? () => widget.onConfirm(AppointmentRescheduleConfirmResult(start: _startTime, end: _endTime))
                : null,
          ),
        ],
      ),
    );
  }
}
