import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

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
    required this.dialogStyle,
    required this.animation,
    super.key,
  });

  final AppointmentListItem appointment;
  final DateTime newStart;
  final DateTime newEnd;
  final BranchWorkingSchedule schedule;
  final List<AppointmentListItem> branchAppointments;
  final FDialogStyle dialogStyle;
  final Animation<double> animation;

  static Future<AppointmentRescheduleConfirmResult?> show(
    BuildContext context, {
    required AppointmentListItem appointment,
    required DateTime newStart,
    required DateTime newEnd,
    required BranchWorkingSchedule schedule,
    required List<AppointmentListItem> branchAppointments,
  }) {
    final fTheme = context.theme;

    return showFDialog<AppointmentRescheduleConfirmResult>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext, style, animation) {
        return FTheme(
          data: fTheme,
          child: AppointmentRescheduleConfirmDialog(
            appointment: appointment,
            newStart: newStart,
            newEnd: newEnd,
            schedule: schedule,
            branchAppointments: branchAppointments,
            dialogStyle: style,
            animation: animation,
          ),
        );
      },
    );
  }

  @override
  State<AppointmentRescheduleConfirmDialog> createState() => _AppointmentRescheduleConfirmDialogState();
}

class _AppointmentRescheduleConfirmDialogState extends State<AppointmentRescheduleConfirmDialog> {
  final _formKey = GlobalKey<FormState>();

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
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final error = _validateTimes();
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }

    Navigator.of(
      context,
      rootNavigator: true,
    ).pop(AppointmentRescheduleConfirmResult(start: _startTime, end: _endTime));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium;
    final labelStyle = bodyStyle?.copyWith(color: colors.mutedForeground);
    final today = DateTime(clock.now().year, clock.now().month, clock.now().day);
    final canMove = _validationError == null;

    return FDialog(
      style: widget.dialogStyle,
      animation: widget.animation,
      direction: Axis.horizontal,
      title: Text('Move appointment?', style: theme.textTheme.titleMedium),
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.appointment.patientName, style: theme.textTheme.titleSmall),
            const SizedBox(height: SpacingTokens.sm),
            Text('From', style: labelStyle),
            Text(_formatRange(widget.appointment.startTime, widget.appointment.endTime), style: bodyStyle),
            const SizedBox(height: SpacingTokens.md),
            Text('To', style: labelStyle),
            const SizedBox(height: SpacingTokens.xs),
            AppDateField(
              key: const Key('appointment_reschedule_pick_date'),
              label: 'Date',
              value: DateTime(_startTime.year, _startTime.month, _startTime.day),
              firstDate: today,
              lastDate: today.add(const Duration(days: 365)),
              onChanged: (date) {
                if (date == null) {
                  return;
                }
                _setStartTime(_combineDateAndTime(date, TimeOfDay.fromDateTime(_startTime)));
                _setEndTime(_combineDateAndTime(date, TimeOfDay.fromDateTime(_endTime)));
              },
            ),
            const SizedBox(height: SpacingTokens.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppClockTimeField(
                    key: const Key('appointment_reschedule_pick_start'),
                    label: 'Start time',
                    value: TimeOfDay.fromDateTime(_startTime),
                    onChanged: (time) {
                      if (time == null) {
                        return;
                      }
                      _setStartTime(_combineDateAndTime(_startTime, time));
                    },
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: AppClockTimeField(
                    key: const Key('appointment_reschedule_pick_end'),
                    label: 'End time',
                    value: TimeOfDay.fromDateTime(_endTime),
                    onChanged: (time) {
                      if (time == null) {
                        return;
                      }
                      _setEndTime(_combineDateAndTime(_endTime, time));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              'Duration: $_durationMinutes min',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: SpacingTokens.sm),
              Text(_validationError!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          key: const Key('appointment_reschedule_confirm'),
          label: 'Move',
          onPressed: canMove ? _confirm : null,
        ),
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  static String _formatRange(DateTime start, DateTime end) {
    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    final day = DateFormat.yMMMd().format(localStart);
    final from = DateFormat.Hm().format(localStart);
    final to = DateFormat.Hm().format(localEnd);
    return '$day · $from – $to';
  }
}
