import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_popover_inputs_shared.dart';

/// Returns true when [a] and [b] fall on the same calendar day.
bool appCalendarIsSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Strips time from [date].
DateTime appCalendarStartOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

/// Parses `dd/mm/yyyy`, `dd-mm-yyyy`, or `dd.mm.yyyy`.
DateTime? appCalendarParseDdMmYyyy(String raw) {
  final parts = raw.split(RegExp(r'[/.-]')).map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((p) => p == null)) return null;
  final day = parts[0]!;
  final month = parts[1]!;
  final year = parts[2]!;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// House display format for a single date (locale-aware, Western digits).
String appCalendarFormatDisplayDate(BuildContext context, DateTime date) {
  final locale = appInputIntlLocale(context);
  return DateFormat.yMMMd(locale).format(date);
}

/// Short range segment (`d MMM`).
String appCalendarFormatShortDate(BuildContext context, DateTime date) {
  final locale = appInputIntlLocale(context);
  return DateFormat('d MMM', locale).format(date);
}

const List<String> _weekdaysEn = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
const List<String> _weekdaysAr = ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'];

List<String> appCalendarWeekdayLabels(BuildContext context) {
  return appInputIsArabic(context) ? _weekdaysAr : _weekdaysEn;
}

List<DateTime?> appCalendarMonthCells(DateTime month) {
  final year = month.year;
  final m = month.month;
  final first = DateTime(year, m, 1);
  final startPad = first.weekday % 7;
  final daysInMonth = DateTime(year, m + 1, 0).day;
  final cells = <DateTime?>[];
  for (var i = 0; i < startPad; i++) {
    cells.add(null);
  }
  for (var d = 1; d <= daysInMonth; d++) {
    cells.add(DateTime(year, m, d));
  }
  return cells;
}

/// Reusable month grid shared by [AppDatePicker] and [AppDateRangePicker].
class AppCalendarGrid extends StatelessWidget {
  const AppCalendarGrid({
    required this.month,
    required this.onDaySelected,
    this.selectedDay,
    this.rangeStart,
    this.rangeEnd,
    this.min,
    this.max,
    this.showHeader = true,
    this.onPreviousMonth,
    this.onNextMonth,
    this.compact = false,
    super.key,
  });

  final DateTime month;
  final ValueChanged<DateTime> onDaySelected;
  final DateTime? selectedDay;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final DateTime? min;
  final DateTime? max;
  final bool showHeader;
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;
  final bool compact;

  bool _isDisabled(DateTime day) {
    final d = appCalendarStartOfDay(day);
    if (min != null && d.isBefore(appCalendarStartOfDay(min!))) return true;
    if (max != null && d.isAfter(appCalendarStartOfDay(max!))) return true;
    return false;
  }

  bool _inRange(DateTime day) {
    if (rangeStart == null || rangeEnd == null) return false;
    final d = appCalendarStartOfDay(day);
    final start = appCalendarStartOfDay(rangeStart!);
    final end = appCalendarStartOfDay(rangeEnd!);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  bool _isRangeEndpoint(DateTime day, DateTime? endpoint) {
    return endpoint != null && appCalendarIsSameDay(day, endpoint);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final weekdays = appCalendarWeekdayLabels(context);
    final cells = appCalendarMonthCells(month);
    final today = appCalendarStartOfDay(DateTime.now());
    final locale = appInputIntlLocale(context);
    final monthLabel = DateFormat.yMMMM(locale).format(month);

    final prevIcon = isRtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft;
    final nextIcon = isRtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight;

    final cellStyle = compact ? typography.caption : typography.bodySm;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              if (onPreviousMonth != null)
                _CalendarNavButton(
                  icon: prevIcon,
                  semanticLabel: 'Previous month',
                  onTap: onPreviousMonth!,
                )
              else
                const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                ),
              ),
              if (onNextMonth != null)
                _CalendarNavButton(
                  icon: nextIcon,
                  semanticLabel: 'Next month',
                  onTap: onNextMonth!,
                )
              else
                const SizedBox(width: AppSpacing.s8),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
        ],
        Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Column(
            children: [
              Row(
                children: [
                  for (final label in weekdays)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: typography.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              for (var row = 0; row < (cells.length / 7).ceil(); row++)
                Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: _buildDayCell(
                          context,
                          row * 7 + col < cells.length ? cells[row * 7 + col] : null,
                          today,
                          cellStyle,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    DateTime? day,
    DateTime today,
    TextStyle cellStyle,
  ) {
    if (day == null) {
      return const SizedBox(height: AppSpacing.s8);
    }

    final colors = context.colors;
    final disabled = _isDisabled(day);
    final selected = selectedDay != null && appCalendarIsSameDay(day, selectedDay!);
    final isToday = appCalendarIsSameDay(day, today);
    final inRange = _inRange(day);
    final isStart = _isRangeEndpoint(day, rangeStart);
    final isEnd = _isRangeEndpoint(day, rangeEnd);
    final isEndpoint = isStart || isEnd;

    Color? bg;
    Color fg = disabled ? colors.textDisabled : colors.textPrimary;
    BoxBorder? border;

    if (isEndpoint) {
      bg = colors.actionPrimary;
      fg = colors.actionPrimaryFg;
    } else if (selected) {
      bg = colors.actionPrimary;
      fg = colors.actionPrimaryFg;
    } else if (inRange) {
      bg = colors.surfaceSelected;
    } else if (isToday) {
      border = Border.all(color: colors.borderFocus);
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s0_5),
      child: AppPressable.builder(
        enabled: !disabled,
        onTap: () => onDaySelected(day),
        semanticLabel: DateFormat.yMMMMd(appInputIntlLocale(context)).format(day),
        borderRadius: AppRadii.mdAll,
        builder: (context, states, _) {
          final hovered = states.contains(WidgetState.hovered);
          return AnimatedContainer(
            duration: AppDurations.instant,
            curve: AppEasings.standard,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.s1 + AppSpacing.s0_5,
            ),
            decoration: BoxDecoration(
              color: bg ?? (hovered && !disabled ? colors.surfaceHover : null),
              border: border,
              borderRadius: AppRadii.mdAll,
            ),
            child: Text(
              '${day.day}',
              style: context.typography.tabular(
                cellStyle.copyWith(color: fg),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CalendarNavButton extends StatelessWidget {
  const _CalendarNavButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable.builder(
      onTap: onTap,
      semanticLabel: semanticLabel,
      borderRadius: AppRadii.mdAll,
      builder: (context, states, _) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: AppDurations.instant,
          padding: const EdgeInsets.all(AppSpacing.s1),
          decoration: BoxDecoration(
            color: hovered ? context.colors.surfaceHover : Colors.transparent,
            borderRadius: AppRadii.mdAll,
          ),
          child: AppIcon(
            icon: icon,
            size: AppIconSize.sm,
            color: context.colors.iconDefault,
          ),
        );
      },
    );
  }
}
