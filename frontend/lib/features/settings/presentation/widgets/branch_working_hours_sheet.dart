import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

const _sheetWidth = 520.0;
const _timeFieldMinWidth = 136.0;

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

/// Right-side sheet for viewing and editing branch working hours.
class BranchWorkingHoursSheet extends StatefulWidget {
  const BranchWorkingHoursSheet({
    required this.initialSchedule,
    required this.onUpdate,
    this.startInEditMode = false,
    this.confirmLabel = 'Update',
    super.key,
  });

  final BranchWorkingSchedule initialSchedule;
  final ValueChanged<BranchWorkingSchedule> onUpdate;

  /// When true, the sheet opens editable with [confirmLabel] (e.g. setup wizard Save).
  final bool startInEditMode;

  /// Primary action label when editing (settings uses Update; setup uses Save).
  final String confirmLabel;

  @override
  State<BranchWorkingHoursSheet> createState() => _BranchWorkingHoursSheetState();
}

class _BranchWorkingHoursSheetState extends State<BranchWorkingHoursSheet> {
  final _formKey = GlobalKey<FormState>();
  late BranchWorkingSchedule _draft;
  var _isEditing = false;
  String? _scheduleError;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialSchedule;
    _isEditing = widget.startInEditMode;
  }

  void _startEditing() => setState(() => _isEditing = true);

  void _closeSheet() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    });
  }

  void _cancel() {
    FocusManager.instance.primaryFocus?.unfocus();
    _closeSheet();
  }

  void _handleUpdate() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final timeRangeError = _invalidTimeRangeError();
    if (timeRangeError != null) {
      setState(() => _scheduleError = timeRangeError);
      return;
    }
    if (!_draft.hasConfiguredWorkingHours) {
      setState(() => _scheduleError = 'At least one working day is required.');
      return;
    }
    widget.onUpdate(_draft);
    _closeSheet();
  }

  void _setDayEnabled(BranchWeekday day, bool enabled) {
    if (!enabled) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
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
      _scheduleError = null;
    });
  }

  /// Inherit open/close from the nearest earlier working day, else 9:00–17:00.
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

  void _setDayTime(BranchWeekday day, {TimeOfDay? open, TimeOfDay? close}) {
    final current = _dayHours(day);
    final nextOpen = open == null ? current.openTime : _formatHm(open);
    final nextClose = close == null ? current.closeTime : _formatHm(close);
    if (nextOpen == current.openTime && nextClose == current.closeTime) {
      return;
    }

    setState(() {
      final days = _draft.days
          .map((entry) {
            if (entry.day != day) {
              return entry;
            }
            return entry.copyWith(openTime: nextOpen, closeTime: nextClose);
          })
          .toList(growable: false);
      _draft = BranchWorkingSchedule(days);
      _scheduleError = null;
    });
  }

  BranchWorkingDayHours _dayHours(BranchWeekday day) {
    return _draft.days.firstWhere((entry) => entry.day == day);
  }

  String? _invalidTimeRangeError() {
    for (final day in BranchWeekday.values) {
      final hours = _dayHours(day);
      if (!hours.isWorkingDay) {
        continue;
      }
      final open = _parseBranchTime(hours.openTime);
      final close = _parseBranchTime(hours.closeTime);
      if (open == null || close == null) {
        continue;
      }
      if (open.hour * 60 + open.minute >= close.hour * 60 + close.minute) {
        return 'Close time must be after open time.';
      }
    }
    return null;
  }

  String? get _displayedScheduleError {
    if (_scheduleError != null) {
      return _scheduleError;
    }
    if (_isEditing) {
      return _invalidTimeRangeError();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Material(
      color: colors.popover,
      child: SizedBox(
        width: _sheetWidth,
        height: MediaQuery.sizeOf(context).height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(
              isEditing: _isEditing,
              showEditButton: !widget.startInEditMode,
              onClose: _closeSheet,
              onEdit: _startEditing,
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, 0, SpacingTokens.lg, SpacingTokens.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < BranchWeekday.values.length; i++) ...[
                        if (i > 0) const SizedBox(height: SpacingTokens.sm),
                        _DayScheduleRow(
                          key: ValueKey(BranchWeekday.values[i]),
                          dayHours: _dayHours(BranchWeekday.values[i]),
                          readOnly: !_isEditing,
                          onEnabledChanged: (enabled) => _setDayEnabled(BranchWeekday.values[i], enabled),
                          onOpenChanged: (time) => _setDayTime(BranchWeekday.values[i], open: time),
                          onCloseChanged: (time) => _setDayTime(BranchWeekday.values[i], close: time),
                          openValidator: () => _timeValidatorFor(BranchWeekday.values[i], isOpen: true),
                          closeValidator: () => _timeValidatorFor(BranchWeekday.values[i], isOpen: false),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
                color: colors.popover,
              ),
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_displayedScheduleError != null) ...[
                      AppAlert(variant: AppAlertVariant.destructive, title: _displayedScheduleError!),
                      const SizedBox(height: SpacingTokens.md),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Cancel',
                            variant: AppButtonVariant.outline,
                            expand: true,
                            onPressed: _cancel,
                          ),
                        ),
                        if (_isEditing) ...[
                          const SizedBox(width: SpacingTokens.md),
                          Expanded(
                            child: AppButton(label: widget.confirmLabel, expand: true, onPressed: _handleUpdate),
                          ),
                        ],
                      ],
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

  String? _timeValidatorFor(BranchWeekday day, {required bool isOpen}) {
    final hours = _dayHours(day);
    if (!hours.isWorkingDay) {
      return null;
    }
    final open = _parseBranchTime(hours.openTime);
    final close = _parseBranchTime(hours.closeTime);
    if (open == null || close == null) {
      return 'Working hours are required for selected days.';
    }
    if (open.hour * 60 + open.minute >= close.hour * 60 + close.minute) {
      return isOpen ? 'Open time must be before close time.' : 'Close time must be after open time.';
    }
    return null;
  }

  static String _formatHm(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.isEditing,
    required this.showEditButton,
    required this.onClose,
    required this.onEdit,
  });

  final bool isEditing;
  final bool showEditButton;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.md, SpacingTokens.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: colors.muted, borderRadius: BorderRadius.circular(context.shapeTokens.md)),
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.sm),
              child: Icon(Icons.schedule_outlined, size: 20, color: colors.foreground),
            ),
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Working hours', style: theme.textTheme.titleLarge?.copyWith(color: colors.foreground)),
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  'Control how this branch operates at different times of day.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                ),
              ],
            ),
          ),
          if (showEditButton && !isEditing)
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: Icon(Icons.edit_outlined, color: colors.mutedForeground),
            ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: Icon(Icons.close, color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _DayScheduleRow extends StatelessWidget {
  const _DayScheduleRow({
    required this.dayHours,
    required this.readOnly,
    required this.onEnabledChanged,
    required this.onOpenChanged,
    required this.onCloseChanged,
    required this.openValidator,
    required this.closeValidator,
    super.key,
  });

  final BranchWorkingDayHours dayHours;
  final bool readOnly;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<TimeOfDay?> onOpenChanged;
  final ValueChanged<TimeOfDay?> onCloseChanged;
  final String? Function() openValidator;
  final String? Function() closeValidator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final enabled = dayHours.isWorkingDay;
    final dayStyle = theme.textTheme.bodyMedium?.copyWith(
      color: enabled ? colors.foreground : colors.mutedForeground,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: SizedBox(
              width: 40,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Transform.scale(
                  scale: 0.82,
                  child: FSwitch(value: enabled, enabled: !readOnly, onChange: readOnly ? null : onEnabledChanged),
                ),
              ),
            ),
          ),
          const SizedBox(width: SpacingTokens.md),
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: SizedBox(
              width: 92,
              child: Text(dayHours.day.label, style: dayStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: SpacingTokens.md),
          Expanded(
            child: enabled
                ? Row(
                    children: [
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: _timeFieldMinWidth),
                          child: AppClockTimeField(
                            key: ValueKey('${dayHours.day.name}-open-${dayHours.openTime}-$readOnly'),
                            label: 'From',
                            size: AppFieldSize.md,
                            enabled: !readOnly,
                            readOnly: readOnly,
                            value: _parseBranchTime(dayHours.openTime),
                            onChanged: onOpenChanged,
                            validator: (_) => openValidator(),
                          ),
                        ),
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: _timeFieldMinWidth),
                          child: AppClockTimeField(
                            key: ValueKey('${dayHours.day.name}-close-${dayHours.closeTime}-$readOnly'),
                            label: 'To',
                            size: AppFieldSize.md,
                            enabled: !readOnly,
                            readOnly: readOnly,
                            value: _parseBranchTime(dayHours.closeTime),
                            onChanged: onCloseChanged,
                            validator: (_) => closeValidator(),
                          ),
                        ),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.nightlight_outlined, size: 16, color: colors.mutedForeground),
                        const SizedBox(width: SpacingTokens.sm),
                        Text('Closed', style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
