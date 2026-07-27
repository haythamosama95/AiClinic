import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/formatting/appointment_range_format.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';

/// Confirmed move times returned from [AppointmentRescheduleConfirmDialog].
class AppointmentRescheduleConfirmResult {
  const AppointmentRescheduleConfirmResult({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// Confirms a calendar drag reschedule after client-side validation passes.
class AppointmentRescheduleConfirmDialog extends StatefulWidget {
  const AppointmentRescheduleConfirmDialog({
    required this.appointment,
    required this.newStart,
    required this.newEnd,
    required this.schedule,
    required this.branchAppointments,
    super.key,
  });

  final AppointmentListItem appointment;
  final DateTime newStart;
  final DateTime newEnd;
  final BranchWorkingSchedule schedule;
  final List<AppointmentListItem> branchAppointments;

  static Future<AppointmentRescheduleConfirmResult?> show(
    BuildContext context, {
    required AppointmentListItem appointment,
    required DateTime newStart,
    required DateTime newEnd,
    required BranchWorkingSchedule schedule,
    required List<AppointmentListItem> branchAppointments,
  }) {
    return AppDialog.show<AppointmentRescheduleConfirmResult>(
      context,
      title: 'Move appointment?',
      size: AppDialogSize.md,
      barrierDismissible: false,
      child: AppointmentRescheduleConfirmDialog(
        appointment: appointment,
        newStart: newStart,
        newEnd: newEnd,
        schedule: schedule,
        branchAppointments: branchAppointments,
      ),
    );
  }

  @override
  State<AppointmentRescheduleConfirmDialog> createState() => _AppointmentRescheduleConfirmDialogState();
}

class _AppointmentRescheduleConfirmDialogState extends State<AppointmentRescheduleConfirmDialog> {
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

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
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

  void _confirm() {
    final error = _validateTimes();
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }

    Navigator.of(context).pop(AppointmentRescheduleConfirmResult(start: _startTime, end: _endTime));
  }

  int? _parseTime(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  TimeOfDay _minutesToTime(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  String _pad(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final today = DateTime(clock.now().year, clock.now().month, clock.now().day);
    final canMove = _validationError == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.appointment.patientName, style: AppTypography.bodyStrong(context)),
        const SizedBox(height: AppSpacing.space3),
        Text('From', style: AppTypography.caption(context).copyWith(color: colors.textSecondary)),
        Text(
          formatAppointmentRange(widget.appointment.startTime, widget.appointment.endTime),
          style: AppTypography.bodySm(context),
        ),
        const SizedBox(height: AppSpacing.space4),
        Text('To', style: AppTypography.caption(context).copyWith(color: colors.textSecondary)),
        const SizedBox(height: AppSpacing.space1),
        AppFormField(
          id: 'appointment_reschedule_pick_date',
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
              _setStartTime(_combineDateAndTime(date, TimeOfDay.fromDateTime(_startTime)));
              _setEndTime(_combineDateAndTime(date, TimeOfDay.fromDateTime(_endTime)));
            },
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppFormField(
                id: 'appointment_reschedule_pick_start',
                label: 'Start time',
                child: AppTimePicker(
                  key: const Key('appointment_reschedule_pick_start'),
                  value: '${_pad(_startTime.hour)}:${_pad(_startTime.minute)}',
                  onChanged: (value) {
                    final minutes = _parseTime(value);
                    if (minutes == null) {
                      return;
                    }
                    _setStartTime(_combineDateAndTime(_startTime, _minutesToTime(minutes)));
                  },
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: AppFormField(
                id: 'appointment_reschedule_pick_end',
                label: 'End time',
                child: AppTimePicker(
                  key: const Key('appointment_reschedule_pick_end'),
                  value: '${_pad(_endTime.hour)}:${_pad(_endTime.minute)}',
                  onChanged: (value) {
                    final minutes = _parseTime(value);
                    if (minutes == null) {
                      return;
                    }
                    _setEndTime(_combineDateAndTime(_endTime, _minutesToTime(minutes)));
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Duration: $_durationMinutes min',
          style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
        ),
        if (_validationError != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(_validationError!, style: AppTypography.bodySm(context).copyWith(color: colors.statusDangerFg)),
        ],
        const SizedBox(height: AppSpacing.space6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppButton(
              key: const Key('appointment_reschedule_confirm'),
              disabled: !canMove,
              onPressed: canMove ? _confirm : null,
              child: const Text('Move'),
            ),
          ],
        ),
      ],
    );
  }

}
