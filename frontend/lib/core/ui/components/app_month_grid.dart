import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

const _weekdaysEn = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
const _weekdaysAr = ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'];

/// Content width of a single month grid inside the date-picker popover (`w-72` − `p-3`).
const appMonthGridWidth = 264.0;

/// Day cell height matching web date picker (`py-1.5` + `text-body-sm`).
const _dayCellHeight = 32.0;

DateTime appDateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool appIsSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isArabicLocale(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'ar';
}

List<String> appWeekdayHeaders(BuildContext context) {
  return _isArabicLocale(context) ? _weekdaysAr : _weekdaysEn;
}

/// Localized month grid used by date pickers (web `MonthGrid`).
class AppMonthGrid extends StatelessWidget {
  const AppMonthGrid({
    required this.month,
    required this.onDaySelect,
    this.selectedDate,
    this.rangeStart,
    this.rangeEnd,
    this.min,
    this.max,
    this.showWeekdayHeaders = false,
    super.key,
  });

  final DateTime month;
  final DateTime? selectedDate;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final DateTime? min;
  final DateTime? max;
  final bool showWeekdayHeaders;
  final ValueChanged<DateTime> onDaySelect;

  List<DateTime?> _buildCells() {
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

  bool _isDisabled(DateTime day) {
    final normalized = appDateOnly(day);
    if (min != null && normalized.isBefore(appDateOnly(min!))) return true;
    if (max != null && normalized.isAfter(appDateOnly(max!))) return true;
    return false;
  }

  bool _inRange(DateTime day) {
    if (rangeStart == null || rangeEnd == null) return false;
    final normalized = appDateOnly(day);
    final start = appDateOnly(rangeStart!);
    final end = appDateOnly(rangeEnd!);
    return !normalized.isBefore(start) && !normalized.isAfter(end);
  }

  bool _isRangeEndpoint(DateTime day) {
    if (rangeStart != null && appIsSameDay(day, rangeStart!)) return true;
    if (rangeEnd != null && appIsSameDay(day, rangeEnd!)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cells = _buildCells();
    final today = appDateOnly(DateTime.now());
    final weekdays = appWeekdayHeaders(context);
    final isRangeMode = rangeStart != null || rangeEnd != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showWeekdayHeaders) ...[
          Row(
            children: [
              for (final label in weekdays)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
                      child: Text(label, style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space1),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final gridWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : appMonthGridWidth;
            final cellWidth = (gridWidth - 6 * AppSpacing.space1) / 7;
            final aspectRatio = cellWidth / _dayCellHeight;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: AppSpacing.space1,
                crossAxisSpacing: AppSpacing.space1,
                childAspectRatio: aspectRatio,
              ),
              itemCount: cells.length,
              itemBuilder: (context, index) {
                final day = cells[index];
                if (day == null) return const SizedBox.shrink();

                final disabled = _isDisabled(day);
                final selected = selectedDate != null && appIsSameDay(day, selectedDate!);
                final isToday = appIsSameDay(day, today);
                final inRange = _inRange(day);
                final isEndpoint = _isRangeEndpoint(day);

                Color background = Colors.transparent;
                Color foreground = disabled ? colors.textDisabled : colors.textPrimary;

                if (isRangeMode) {
                  if (isEndpoint) {
                    background = colors.actionPrimary;
                    foreground = colors.actionPrimaryFg;
                  } else if (inRange) {
                    background = colors.surfaceSelected;
                  }
                } else if (selected) {
                  background = colors.actionPrimary;
                  foreground = colors.actionPrimaryFg;
                }

                final showTodayBorder = isToday && !selected && !isEndpoint;
                final focusBorder = Theme.of(context).brightness == Brightness.dark
                    ? AppColorPrimitives.teal400
                    : AppColorPrimitives.teal500;

                return Semantics(
                  button: true,
                  enabled: !disabled,
                  selected: selected || isEndpoint,
                  child: Material(
                    color: background,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: disabled ? null : () => onDaySelect(day),
                      child: showTodayBorder
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                border: Border.all(color: focusBorder),
                              ),
                              child: Center(
                                child: Text(
                                  '${day.day}',
                                  style: AppTypography.bodySm(
                                    context,
                                  ).copyWith(color: foreground, fontFeatures: const [FontFeature.tabularFigures()]),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                '${day.day}',
                                style: AppTypography.bodySm(
                                  context,
                                ).copyWith(color: foreground, fontFeatures: const [FontFeature.tabularFigures()]),
                              ),
                            ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
