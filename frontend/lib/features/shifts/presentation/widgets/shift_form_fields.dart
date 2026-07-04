import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/ui.dart';

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
  final String? startTime;
  final String? endTime;
  final TextEditingController notesController;
  final ValueChanged<DateTime?> onShiftDateChanged;
  final ValueChanged<String?> onStartTimeChanged;
  final ValueChanged<String?> onEndTimeChanged;
  final bool enabled;

  static const maxNotesLength = 500;

  DateTime get _today {
    final now = clock.now();
    return DateTime(now.year, now.month, now.day);
  }

  String? _validateEndAfterStart() {
    if (startTime == null || endTime == null) {
      return null;
    }
    final start = _parseHm(startTime!);
    final end = _parseHm(endTime!);
    if (end <= start) {
      return 'End time must be after start time.';
    }
    return null;
  }

  int _parseHm(String value) {
    final parts = value.split(':');
    if (parts.length < 2) {
      return 0;
    }
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return hour * 60 + minute;
  }

  @override
  Widget build(BuildContext context) {
    final timeRangeError = _validateEndAfterStart();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFormField(
          label: 'Shift date',
          requiredMark: true,
          child: AppDatePicker(
            key: const Key('shift_date_field'),
            value: shiftDate,
            min: _today,
            max: _today.add(const Duration(days: 365)),
            disabled: !enabled,
            onChanged: onShiftDateChanged,
          ),
        ),
        AppFormField(
          label: 'Start time',
          requiredMark: true,
          child: AppTimePicker(
            key: const Key('shift_start_time_field'),
            value: startTime,
            disabled: !enabled,
            onChanged: enabled ? onStartTimeChanged : null,
          ),
        ),
        AppFormField(
          label: 'End time',
          requiredMark: true,
          error: timeRangeError,
          child: AppTimePicker(
            key: const Key('shift_end_time_field'),
            value: endTime,
            disabled: !enabled,
            invalid: timeRangeError != null,
            onChanged: enabled ? onEndTimeChanged : null,
          ),
        ),
        AppFormField(
          label: 'Notes (optional)',
          helperText: 'Coverage details, up to $maxNotesLength characters',
          child: AppTextField(
            key: const Key('shift_notes_field'),
            controller: notesController,
            disabled: !enabled,
            readOnly: !enabled,
            keyboardType: TextInputType.multiline,
            maxLines: 4,
            inputFormatters: [LengthLimitingTextInputFormatter(maxNotesLength)],
          ),
        ),
      ],
    );
  }
}
