import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/date_picker.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/picker_trigger.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';
import 'package:ai_clinic/core/ui/widgets/overlay/app_popover.dart';

/// Inclusive date range value.
class DateRange {
  const DateRange({this.start, this.end});

  final DateTime? start;
  final DateTime? end;

  DateRange copyWith({DateTime? start, DateTime? end}) =>
      DateRange(start: start ?? this.start, end: end ?? this.end);
}

/// Preset shortcut for [AppDateRangePicker].
class AppDateRangePreset {
  const AppDateRangePreset({required this.label, required this.range});

  final String label;
  final DateRange range;
}

List<AppDateRangePreset> defaultDateRangePresets() {
  final today = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  final weekStart = today.subtract(Duration(days: today.weekday % 7));
  final weekEnd = weekStart.add(const Duration(days: 6));
  final monthStart = DateTime(today.year, today.month, 1);
  final monthEnd = DateTime(today.year, today.month + 1, 0);
  return [
    AppDateRangePreset(
      label: 'Today',
      range: DateRange(start: today, end: today),
    ),
    AppDateRangePreset(
      label: 'This week',
      range: DateRange(start: weekStart, end: weekEnd),
    ),
    AppDateRangePreset(
      label: 'This month',
      range: DateRange(start: monthStart, end: monthEnd),
    ),
  ];
}

/// Dual-calendar date range picker with presets.
class AppDateRangePicker extends StatefulWidget {
  const AppDateRangePicker({
    super.key,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.value,
    this.presets,
    this.placeholder = 'Select date range',
    this.localeCode,
    this.onValueChange,
  });

  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final DateRange? value;
  final List<AppDateRangePreset>? presets;
  final String placeholder;
  final String? localeCode;
  final ValueChanged<DateRange>? onValueChange;

  @override
  State<AppDateRangePicker> createState() => _AppDateRangePickerState();
}

class _AppDateRangePickerState extends State<AppDateRangePicker> {
  bool _open = false;
  late DateTime _leftMonth;

  @override
  void initState() {
    super.initState();
    _leftMonth = DateTime.now();
  }

  String get _locale {
    final code =
        widget.localeCode ?? Localizations.localeOf(context).languageCode;
    return code == 'ar' ? 'ar-EG' : 'en-GB';
  }

  String _formatRange(DateRange range) {
    final fmt = DateFormat('d MMM', _locale);
    if (range.start == null && range.end == null) return '';
    if (range.start != null && range.end == null) {
      return fmt.format(range.start!);
    }
    if (range.start != null && range.end != null) {
      return '${fmt.format(range.start!)} – ${fmt.format(range.end!)}';
    }
    return '';
  }

  void _handleSelect(DateTime day) {
    final current = widget.value ?? const DateRange();
    DateRange next;
    if (current.start == null ||
        (current.start != null && current.end != null)) {
      next = DateRange(start: day, end: null);
    } else if (day.isBefore(current.start!)) {
      next = DateRange(start: day, end: current.start);
    } else {
      next = DateRange(start: current.start, end: day);
    }
    widget.onValueChange?.call(next);
    if (next.start != null && next.end != null) {
      setState(() => _open = false);
    }
  }

  void _applyPreset(DateRange range) {
    widget.onValueChange?.call(range);
    setState(() => _open = false);
  }

  String? get _helperMessage {
    final range = widget.value;
    if (range == null) return null;
    if (range.start != null && range.end != null) {
      return 'Inclusive range: ${_formatRange(range)}';
    }
    if (range.start != null) return 'Select end date';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final range = widget.value ?? const DateRange();
    final presets = widget.presets ?? defaultDateRangePresets();
    final rightMonth = DateTime(_leftMonth.year, _leftMonth.month + 1, 1);
    final localeCode =
        widget.localeCode ?? Localizations.localeOf(context).languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPopover(
          open: _open && !widget.disabled,
          onOpenChange: (v) => setState(() => _open = v),
          contentPadding: const EdgeInsets.all(AppSpacing.s4),
          trigger: appPickerTriggerShell(
            context: context,
            size: widget.size,
            invalid: widget.invalid,
            disabled: widget.disabled,
            focused: _open,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TextField(
                  readOnly: true,
                  enabled: !widget.disabled,
                  controller: TextEditingController(text: _formatRange(range)),
                  onTap: () {
                    if (!widget.disabled) setState(() => _open = true);
                  },
                  style: AppInputStyles.textStyle(
                    context,
                    widget.size,
                  ).copyWith(color: colors.textPrimary),
                  cursorColor: colors.borderFocus,
                  decoration: AppInputStyles.bareInputDecoration(
                    context,
                    hintText: widget.placeholder,
                    disabled: widget.disabled,
                  ),
                ),
                PositionedDirectional(
                  end: AppSpacing.s3,
                  child: IgnorePointer(
                    child: Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: colors.iconMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: [
                  for (final preset in presets)
                    OutlinedButton(
                      onPressed: () => _applyPreset(preset.range),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s3,
                          vertical: AppSpacing.s2,
                        ),
                        side: BorderSide(color: colors.borderDefault),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.mdAll,
                        ),
                      ),
                      child: Text(
                        preset.label,
                        style: typography.bodySm.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppCalendarGrid(
                      viewMonth: _leftMonth,
                      selected: null,
                      rangeStart: range.start,
                      rangeEnd: range.end,
                      localeCode: localeCode,
                      onSelect: _handleSelect,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Expanded(
                    child: AppCalendarGrid(
                      viewMonth: rightMonth,
                      selected: null,
                      rangeStart: range.start,
                      rangeEnd: range.end,
                      localeCode: localeCode,
                      onSelect: _handleSelect,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _leftMonth = DateTime(
                        _leftMonth.year,
                        _leftMonth.month - 1,
                        1,
                      );
                    }),
                    child: Text(
                      'Previous',
                      style: typography.caption.copyWith(
                        color: colors.textLink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _leftMonth = DateTime(
                        _leftMonth.year,
                        _leftMonth.month + 1,
                        1,
                      );
                    }),
                    child: Text(
                      'Next',
                      style: typography.caption.copyWith(
                        color: colors.textLink,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_helperMessage != null) ...[
          const SizedBox(height: AppSpacing.s1),
          Text(
            _helperMessage!,
            style: typography.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}
