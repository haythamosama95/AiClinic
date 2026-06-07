import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/widgets/app_form_field.dart';

/// Shared shift date/time/notes inputs (V1-7 US1).
class ShiftFormFields extends StatelessWidget {
  const ShiftFormFields({
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    required this.notesController,
    required this.onShiftDateChanged,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
    this.enabled = true,
    super.key,
  });

  final DateTime? shiftDate;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final TextEditingController notesController;
  final ValueChanged<DateTime?> onShiftDateChanged;
  final ValueChanged<TimeOfDay?> onStartTimeChanged;
  final ValueChanged<TimeOfDay?> onEndTimeChanged;
  final bool enabled;

  static const maxNotesLength = 500;

  DateTime get _today {
    final now = clock.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate(BuildContext context) async {
    if (!enabled) {
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: shiftDate ?? _today,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 365)),
    );
    if (picked != null) {
      onShiftDateChanged(DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTime(BuildContext context, {required bool isStart}) async {
    if (!enabled) {
      return;
    }
    final initial = isStart ? startTime : endTime;
    final picked = await showTimePicker(context: context, initialTime: initial ?? const TimeOfDay(hour: 9, minute: 0));
    if (picked != null) {
      if (isStart) {
        onStartTimeChanged(picked);
      } else {
        onEndTimeChanged(picked);
      }
    }
  }

  String _timeLabel(BuildContext context, TimeOfDay? value) {
    if (value == null) {
      return 'Not selected';
    }
    return MaterialLocalizations.of(context).formatTimeOfDay(value);
  }

  String? _validateEndAfterStart() {
    final start = startTime;
    final end = endTime;
    if (start == null || end == null) {
      return null;
    }
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes) {
      return 'End time must be after start time.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = shiftDate == null
        ? 'Not selected'
        : MaterialLocalizations.of(context).formatMediumDate(shiftDate!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const Key('shift_date_field'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Shift date'),
          subtitle: Text(dateLabel),
          trailing: const Icon(Icons.calendar_today),
          enabled: enabled,
          onTap: () => _pickDate(context),
        ),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('shift_start_time_field'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Start time'),
          subtitle: Text(_timeLabel(context, startTime)),
          trailing: const Icon(Icons.schedule),
          enabled: enabled,
          onTap: () => _pickTime(context, isStart: true),
        ),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('shift_end_time_field'),
          contentPadding: EdgeInsets.zero,
          title: const Text('End time'),
          subtitle: Text(_timeLabel(context, endTime)),
          trailing: const Icon(Icons.schedule),
          enabled: enabled,
          onTap: () => _pickTime(context, isStart: false),
        ),
        if (_validateEndAfterStart() != null) ...[
          const SizedBox(height: 8),
          Text(_validateEndAfterStart()!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        AppFormField(
          key: const Key('shift_notes_field'),
          label: 'Notes (optional)',
          hint: 'Coverage details, up to $maxNotesLength characters',
          controller: notesController,
          enabled: enabled,
          keyboardType: TextInputType.multiline,
          maxLength: maxNotesLength,
          maxLines: 4,
          validator: (value) {
            final length = (value ?? '').trim().length;
            if (length > maxNotesLength) {
              return 'Notes must be $maxNotesLength characters or fewer.';
            }
            return null;
          },
        ),
      ],
    );
  }
}
