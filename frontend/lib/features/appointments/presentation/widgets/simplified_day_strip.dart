import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Horizontal day strip with centered selection and chevron navigation (011).
class SimplifiedDayStrip extends StatelessWidget {
  const SimplifiedDayStrip({
    required this.selectedDate,
    required this.onDateSelected,
    this.minDate,
    this.maxDate,
    this.visibleDayCount = 7,
    super.key,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final DateTime? minDate;
  final DateTime? maxDate;
  final int visibleDayCount;

  static const int defaultVisibleDayCount = 7;

  @override
  Widget build(BuildContext context) {
    final range = simplifiedBookingDateRange();
    final min = minDate ?? range.minDate;
    final max = maxDate ?? range.maxDate;
    final selected = clampSimplifiedBookingDate(selectedDate);
    final weekdayFormat = DateFormat.E();
    final canGoBack = selected.isAfter(min);
    final canGoForward = selected.isBefore(max);
    final days = _visibleDays(selected: selected, min: min, max: max);

    return Row(
      children: [
        _NavigationButton(
          icon: Icons.chevron_left,
          tooltip: 'Previous day',
          enabled: canGoBack,
          onPressed: canGoBack
              ? () => onDateSelected(clampSimplifiedBookingDate(selected.subtract(const Duration(days: 1))))
              : null,
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final day in days)
                Expanded(
                  child: _DayCell(
                    date: day,
                    weekdayLabel: weekdayFormat.format(day),
                    isSelected: _isSameDay(day, selected),
                    onTap: () => onDateSelected(day),
                  ),
                ),
            ],
          ),
        ),
        _NavigationButton(
          icon: Icons.chevron_right,
          tooltip: 'Next day',
          enabled: canGoForward,
          onPressed: canGoForward
              ? () => onDateSelected(clampSimplifiedBookingDate(selected.add(const Duration(days: 1))))
              : null,
        ),
      ],
    );
  }

  List<DateTime> _visibleDays({required DateTime selected, required DateTime min, required DateTime max}) {
    final window = visibleDayCount.clamp(1, 31);
    final halfWindow = window ~/ 2;

    var start = selected.subtract(Duration(days: halfWindow));
    var end = selected.add(Duration(days: window - halfWindow - 1));

    if (start.isBefore(min)) {
      final shift = min.difference(start).inDays;
      start = min;
      end = end.add(Duration(days: shift));
    }
    if (end.isAfter(max)) {
      final shift = end.difference(max).inDays;
      end = max;
      start = start.subtract(Duration(days: shift));
      if (start.isBefore(min)) {
        start = min;
      }
    }

    final days = <DateTime>[];
    for (var day = start; !day.isAfter(end); day = day.add(const Duration(days: 1))) {
      days.add(day);
    }
    return days;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({required this.icon, required this.tooltip, required this.enabled, this.onPressed});

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: enabled ? colors.foreground : colors.mutedForeground),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.date, required this.weekdayLabel, required this.isSelected, required this.onTap});

  final DateTime date;
  final String weekdayLabel;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final dateLabel = DateFormat.yMMMMd().format(date);
    final semanticsLabel = isSelected ? 'Selected, $dateLabel' : dateLabel;

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.shapeTokens.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm, horizontal: SpacingTokens.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weekdayLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected ? colors.primary : colors.mutedForeground,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: SpacingTokens.xs),
              Text(
                '${date.day}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isSelected ? colors.primary : colors.foreground,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  decoration: isSelected ? TextDecoration.underline : null,
                  decorationColor: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
