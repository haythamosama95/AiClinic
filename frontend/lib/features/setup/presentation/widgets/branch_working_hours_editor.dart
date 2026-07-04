import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

/// Opens a dialog to configure [BranchWorkingSchedule] for bootstrap setup.
Future<BranchWorkingSchedule?> showBranchWorkingHoursEditor(
  BuildContext context, {
  required BranchWorkingSchedule initialSchedule,
}) {
  return showAppDialog<BranchWorkingSchedule>(
    context,
    size: AppDialogSize.lg,
    builder: (dialogContext, close) {
      return _BranchWorkingHoursEditorDialog(
        initialSchedule: initialSchedule,
        onSave: (schedule) => close(schedule),
        onCancel: () => close(),
      );
    },
  );
}

class _BranchWorkingHoursEditorDialog extends StatefulWidget {
  const _BranchWorkingHoursEditorDialog({
    required this.initialSchedule,
    required this.onSave,
    required this.onCancel,
  });

  final BranchWorkingSchedule initialSchedule;
  final ValueChanged<BranchWorkingSchedule> onSave;
  final VoidCallback onCancel;

  @override
  State<_BranchWorkingHoursEditorDialog> createState() => _BranchWorkingHoursEditorDialogState();
}

class _BranchWorkingHoursEditorDialogState extends State<_BranchWorkingHoursEditorDialog> {
  late BranchWorkingSchedule _draft;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialSchedule;
  }

  BranchWorkingDayHours _dayHours(BranchWeekday day) {
    return _draft.days.firstWhere((entry) => entry.day == day);
  }

  void _setDayEnabled(BranchWeekday day, bool enabled) {
    setState(() {
      final days = _draft.days
          .map((entry) {
            if (entry.day != day) {
              return entry;
            }
            if (!enabled) {
              return entry.copyWith(isWorkingDay: false, openTime: null, closeTime: null);
            }
            final inherited = _inheritedTimesFor(day);
            return entry.copyWith(isWorkingDay: true, openTime: inherited.$1, closeTime: inherited.$2);
          })
          .toList(growable: false);
      _draft = BranchWorkingSchedule(days);
      _summaryError = null;
    });
  }

  (String, String) _inheritedTimesFor(BranchWeekday day) {
    const defaultOpen = '09:00';
    const defaultClose = '17:00';

    final dayIndex = BranchWeekday.values.indexOf(day);
    for (var i = dayIndex - 1; i >= 0; i--) {
      final previous = _dayHours(BranchWeekday.values[i]);
      if (previous.isWorkingDay && previous.openTime != null && previous.closeTime != null) {
        return (previous.openTime!, previous.closeTime!);
      }
    }
    return (defaultOpen, defaultClose);
  }

  void _setDayTime(BranchWeekday day, {String? openTime, String? closeTime}) {
    setState(() {
      final days = _draft.days
          .map((entry) {
            if (entry.day != day) {
              return entry;
            }
            return entry.copyWith(
              openTime: openTime ?? entry.openTime,
              closeTime: closeTime ?? entry.closeTime,
            );
          })
          .toList(growable: false);
      _draft = BranchWorkingSchedule(days);
      _summaryError = null;
    });
  }

  String? _invalidTimeRangeError() {
    for (final day in _draft.days) {
      if (!day.isWorkingDay) {
        continue;
      }
      final open = _parseBranchTime(day.openTime);
      final close = _parseBranchTime(day.closeTime);
      if (open == null || close == null) {
        return 'Working hours are required for selected days.';
      }
      if (open.hour * 60 + open.minute >= close.hour * 60 + close.minute) {
        return 'Open time must be before close time for ${day.day.label}.';
      }
    }
    return null;
  }

  void _handleSave() {
    final rangeError = _invalidTimeRangeError();
    if (rangeError != null) {
      setState(() => _summaryError = rangeError);
      return;
    }
    if (!_draft.hasConfiguredWorkingHours) {
      setState(() => _summaryError = 'At least one working day is required.');
      return;
    }
    widget.onSave(_draft);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Working hours',
      description: 'Control how this branch operates at different times of day.',
      size: AppDialogSize.lg,
      onClose: widget.onCancel,
      body: AppScrollArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_summaryError != null) ...[
              AppAlert(variant: AppAlertVariant.danger, title: _summaryError!),
              const SizedBox(height: AppSpacing.s4),
            ],
            for (final day in BranchWeekday.values) ...[
              _DayScheduleRow(
                dayHours: _dayHours(day),
                onEnabledChanged: (enabled) => _setDayEnabled(day, enabled),
                onOpenChanged: (value) => _setDayTime(day, openTime: value),
                onCloseChanged: (value) => _setDayTime(day, closeTime: value),
              ),
              if (day != BranchWeekday.values.last) const SizedBox(height: AppSpacing.s3),
            ],
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: widget.onCancel,
          ),
          const SizedBox(width: AppSpacing.s3),
          AppButton(label: 'Save', onPressed: _handleSave),
        ],
      ),
    );
  }
}

class _DayScheduleRow extends StatefulWidget {
  const _DayScheduleRow({
    required this.dayHours,
    required this.onEnabledChanged,
    required this.onOpenChanged,
    required this.onCloseChanged,
  });

  final BranchWorkingDayHours dayHours;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onOpenChanged;
  final ValueChanged<String> onCloseChanged;

  @override
  State<_DayScheduleRow> createState() => _DayScheduleRowState();
}

class _DayScheduleRowState extends State<_DayScheduleRow> {
  late final TextEditingController _openController;
  late final TextEditingController _closeController;
  String? _openError;
  String? _closeError;

  @override
  void initState() {
    super.initState();
    _openController = TextEditingController(text: widget.dayHours.openTime ?? '');
    _closeController = TextEditingController(text: widget.dayHours.closeTime ?? '');
  }

  @override
  void didUpdateWidget(covariant _DayScheduleRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayHours.openTime != widget.dayHours.openTime) {
      _openController.text = widget.dayHours.openTime ?? '';
    }
    if (oldWidget.dayHours.closeTime != widget.dayHours.closeTime) {
      _closeController.text = widget.dayHours.closeTime ?? '';
    }
  }

  @override
  void dispose() {
    _openController.dispose();
    _closeController.dispose();
    super.dispose();
  }

  String? _validateTime(String? raw, {required bool isOpen}) {
    final hours = widget.dayHours;
    if (!hours.isWorkingDay) {
      return null;
    }
    final parsed = _parseBranchTime(raw);
    if (parsed == null) {
      return 'Enter a valid time (HH:MM).';
    }
    final open = _parseBranchTime(hours.openTime);
    final close = _parseBranchTime(hours.closeTime);
    if (open != null && close != null && open.hour * 60 + open.minute >= close.hour * 60 + close.minute) {
      return isOpen ? 'Open time must be before close time.' : 'Close time must be after open time.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final enabled = widget.dayHours.isWorkingDay;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: AppSpacing.s6),
          child: AppCheckbox(
            value: enabled,
            onChanged: (checked) => widget.onEnabledChanged(checked ?? false),
            semanticLabel: '${widget.dayHours.day.label} working day',
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        SizedBox(
          width: 96,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.s6),
            child: Text(
              widget.dayHours.day.label,
              style: typography.bodyStrong.copyWith(
                color: enabled ? colors.textPrimary : colors.textTertiary,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: enabled
              ? Row(
                  children: [
                    Expanded(
                      child: AppFormField(
                        label: 'From',
                        error: _openError,
                        child: AppTextField(
                          controller: _openController,
                          hintText: '09:00',
                          onChanged: (value) {
                            widget.onOpenChanged(value);
                            setState(() => _openError = _validateTime(value, isOpen: true));
                          },
                          invalid: _openError != null,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    Expanded(
                      child: AppFormField(
                        label: 'To',
                        error: _closeError,
                        child: AppTextField(
                          controller: _closeController,
                          hintText: '17:00',
                          onChanged: (value) {
                            widget.onCloseChanged(value);
                            setState(() => _closeError = _validateTime(value, isOpen: false));
                          },
                          invalid: _closeError != null,
                        ),
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsetsDirectional.only(top: AppSpacing.s6),
                  child: Text(
                    'Closed',
                    style: typography.body.copyWith(color: colors.textTertiary),
                  ),
                ),
        ),
      ],
    );
  }
}

TimeOfDay? _parseBranchTime(String? input) {
  final normalized = input?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(normalized);
  if (match == null) {
    return null;
  }
  return TimeOfDay(hour: int.parse(match.group(1)!), minute: int.parse(match.group(2)!));
}
