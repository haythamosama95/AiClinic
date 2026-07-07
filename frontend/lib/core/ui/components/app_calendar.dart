import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_segmented_control.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Calendar display mode (web `CalendarView`).
enum CalendarView { day, week, month }

/// A single event on the calendar grid.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.patient,
    this.doctor,
    this.conflict = false,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? patient;
  final String? doctor;
  final bool conflict;
}

/// Application-owned calendar (`04-components` display).
///
/// Month / week / day views with localized weekday glyphs. Requires
/// [ensureIntlDateFormattingInitialized] at app startup before locale-specific
/// [DateFormat] use.
class AppCalendar extends StatefulWidget {
  const AppCalendar({this.events = const [], this.view, this.date, this.onViewChange, this.onDateChange, super.key});

  final List<CalendarEvent> events;
  final CalendarView? view;
  final DateTime? date;
  final ValueChanged<CalendarView>? onViewChange;
  final ValueChanged<DateTime>? onDateChange;

  @override
  State<AppCalendar> createState() => _AppCalendarState();
}

class _AppCalendarState extends State<AppCalendar> {
  static const _hours = [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19];
  static final _defaultDate = DateTime(2026, 7, 4);

  late CalendarView _internalView = CalendarView.week;
  late DateTime _internalDate = _defaultDate;

  CalendarView get _view => widget.view ?? _internalView;
  DateTime get _currentDate => widget.date ?? _internalDate;

  void _setView(CalendarView view) {
    widget.onViewChange?.call(view);
    if (widget.view == null) {
      setState(() => _internalView = view);
    }
  }

  void _setDate(DateTime date) {
    widget.onDateChange?.call(date);
    if (widget.date == null) {
      setState(() => _internalDate = date);
    }
  }

  void _navigate(int delta) {
    final next = DateTime(_currentDate.year, _currentDate.month, _currentDate.day);
    switch (_view) {
      case CalendarView.month:
        _setDate(DateTime(next.year, next.month + delta, next.day));
      case CalendarView.week:
        _setDate(next.add(Duration(days: delta * 7)));
      case CalendarView.day:
        _setDate(next.add(Duration(days: delta)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final locale = _localeTag(context);
    final labels = _CalendarLabels.of(context);
    final weekStart = _startOfWeek(_currentDate);
    final weekDays = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final monthDays = _monthDays(_currentDate.year, _currentDate.month);
    final title = _title(context, locale, weekDays);
    final today = DateTime.now();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CalendarHeader(
            colors: colors,
            title: title,
            labels: labels,
            view: _view,
            onPrevious: () => _navigate(-1),
            onNext: () => _navigate(1),
            onViewChange: _setView,
            onToday: () => _setDate(DateTime(today.year, today.month, today.day)),
          ),
          if (_view == CalendarView.month)
            _MonthView(colors: colors, locale: locale, monthDays: monthDays, events: widget.events, today: today)
          else
            _TimeGridView(
              colors: colors,
              locale: locale,
              view: _view,
              days: _view == CalendarView.day ? [_currentDate] : weekDays,
              hours: _hours,
              events: widget.events,
              today: today,
            ),
        ],
      ),
    );
  }

  String _localeTag(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ar' ? 'ar-EG' : 'en-GB';
  }

  String _title(BuildContext context, String locale, List<DateTime> weekDays) {
    switch (_view) {
      case CalendarView.month:
        return DateFormat.yMMMM(locale).format(_currentDate);
      case CalendarView.week:
        final start = DateFormat.MMMd(locale).format(weekDays.first);
        final end = DateFormat.yMMMd(locale).format(weekDays.last);
        return '$start – $end';
      case CalendarView.day:
        return DateFormat.yMMMMEEEEd(locale).format(_currentDate);
    }
  }
}

class _CalendarLabels {
  const _CalendarLabels({
    required this.previous,
    required this.next,
    required this.day,
    required this.week,
    required this.month,
    required this.today,
    required this.viewAriaLabel,
    required this.currentTime,
  });

  final String previous;
  final String next;
  final String day;
  final String week;
  final String month;
  final String today;
  final String viewAriaLabel;
  final String currentTime;

  static _CalendarLabels of(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    if (isAr) {
      return const _CalendarLabels(
        previous: 'السابق',
        next: 'التالي',
        day: 'يوم',
        week: 'أسبوع',
        month: 'شهر',
        today: 'اليوم',
        viewAriaLabel: 'عرض التقويم',
        currentTime: 'الوقت الحالي',
      );
    }
    return const _CalendarLabels(
      previous: 'Previous',
      next: 'Next',
      day: 'Day',
      week: 'Week',
      month: 'Month',
      today: 'Today',
      viewAriaLabel: 'Calendar view',
      currentTime: 'Current time',
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.colors,
    required this.title,
    required this.labels,
    required this.view,
    required this.onPrevious,
    required this.onNext,
    required this.onViewChange,
    required this.onToday,
  });

  final AppSemanticColors colors;
  final String title;
  final _CalendarLabels labels;
  final CalendarView view;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<CalendarView> onViewChange;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.space3,
          runSpacing: AppSpacing.space3,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconButton(
                  icon: const Icon(Icons.chevron_left),
                  label: labels.previous,
                  size: AppIconButtonSize.sm,
                  onPressed: onPrevious,
                ),
                AppIconButton(
                  icon: const Icon(Icons.chevron_right),
                  label: labels.next,
                  size: AppIconButtonSize.sm,
                  onPressed: onNext,
                ),
                const SizedBox(width: AppSpacing.space2),
                Text(title, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
              ],
            ),
            AppSegmentedControl<String>(
              value: view.name,
              ariaLabel: labels.viewAriaLabel,
              size: AppSegmentedControlSize.sm,
              options: [
                SegmentedOption(value: 'day', label: Text(labels.day)),
                SegmentedOption(value: 'week', label: Text(labels.week)),
                SegmentedOption(value: 'month', label: Text(labels.month)),
              ],
              onChanged: (value) => onViewChange(CalendarView.values.byName(value)),
            ),
            AppButton(
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: onToday,
              child: Text(labels.today),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.colors,
    required this.locale,
    required this.monthDays,
    required this.events,
    required this.today,
  });

  final AppSemanticColors colors;
  final String locale;
  final List<DateTime?> monthDays;
  final List<CalendarEvent> events;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final weekdayLabels = _weekdayLabels(locale);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dangerSurface = isDark ? AppColorPrimitives.statusDangerSurfaceDark : AppColorPrimitives.red50;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppTypography.overline(context).copyWith(color: colors.textTertiary),
                    ),
                  ),
                ),
            ],
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisExtent: 80),
            itemCount: monthDays.length,
            itemBuilder: (context, index) {
              final day = monthDays[index];
              if (day == null) {
                return const SizedBox.shrink();
              }

              final dayEvents = _eventsForDay(events, day);
              final isToday = _isSameDay(day, today);

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isToday ? colors.surfaceSelected : null,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: Colors.transparent),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${day.day}',
                          style: AppTypography.caption(
                            context,
                          ).copyWith(color: colors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                        const SizedBox(height: AppSpacing.space1),
                        for (final event in dayEvents.take(2))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: event.conflict ? dangerSurface : colors.surfaceSelected,
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space1, vertical: 2),
                                child: Text(
                                  event.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.caption(
                                    context,
                                  ).copyWith(color: event.conflict ? colors.statusDangerFg : colors.textLink),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TimeGridView extends StatelessWidget {
  const _TimeGridView({
    required this.colors,
    required this.locale,
    required this.view,
    required this.days,
    required this.hours,
    required this.events,
    required this.today,
  });

  final AppSemanticColors colors;
  final String locale;
  final CalendarView view;
  final List<DateTime> days;
  final List<int> hours;
  final List<CalendarEvent> events;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final weekdayFormat = DateFormat.E(locale);
    final labels = _CalendarLabels.of(context);
    final minWidth = view == CalendarView.day ? 56.0 + 200 : 640.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: minWidth,
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 56),
                  for (var i = 0; i < days.length; i++)
                    Expanded(
                      child: _DayColumnHeader(
                        colors: colors,
                        day: days[i],
                        weekday: weekdayFormat.format(days[i]),
                        isToday: _isSameDay(days[i], today),
                        isLast: i == days.length - 1,
                      ),
                    ),
                ],
              ),
            ),
            for (final hour in hours)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: colors.borderSubtle),
                            right: BorderSide(color: colors.borderSubtle),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space2,
                            vertical: AppSpacing.space3,
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              _formatHour(hour),
                              style: AppTypography.caption(context).copyWith(
                                color: colors.textTertiary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < days.length; i++)
                      Expanded(
                        child: _HourCell(
                          colors: colors,
                          day: days[i],
                          hour: hour,
                          events: events,
                          isToday: _isSameDay(days[i], today),
                          isLast: i == days.length - 1,
                          nowHour: today.hour,
                          currentTimeLabel: labels.currentTime,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayColumnHeader extends StatelessWidget {
  const _DayColumnHeader({
    required this.colors,
    required this.day,
    required this.weekday,
    required this.isToday,
    required this.isLast,
  });

  final AppSemanticColors colors;
  final DateTime day;
  final String weekday;
  final bool isToday;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isToday ? colors.surfaceSelected : null,
        border: Border(right: isLast ? BorderSide.none : BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space2),
        child: Column(
          children: [
            Text(weekday, style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
            Text(
              '${day.day}',
              style: AppTypography.bodyStrong(
                context,
              ).copyWith(color: colors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _HourCell extends StatelessWidget {
  const _HourCell({
    required this.colors,
    required this.day,
    required this.hour,
    required this.events,
    required this.isToday,
    required this.isLast,
    required this.nowHour,
    required this.currentTimeLabel,
  });

  final AppSemanticColors colors;
  final DateTime day;
  final int hour;
  final List<CalendarEvent> events;
  final bool isToday;
  final bool isLast;
  final int nowHour;
  final String currentTimeLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dangerSurface = isDark ? AppColorPrimitives.statusDangerSurfaceDark : AppColorPrimitives.red50;
    final dayEvents = events.where((e) => _isSameDay(e.start, day) && e.start.hour == hour);

    final showNow = isToday && nowHour == hour;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.borderSubtle),
          right: isLast ? BorderSide.none : BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Stack(
        children: [
          if (showNow)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.center,
                child: Semantics(
                  label: currentTimeLabel,
                  child: Container(height: 2, color: colors.actionPrimary),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final event in dayEvents)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space1),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: event.conflict ? dangerSurface : colors.surfaceSelected,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: event.conflict ? Border.all(color: colors.statusDangerBorder) : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space1),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: AppTypography.caption(context).copyWith(
                                color: event.conflict ? colors.statusDangerFg : colors.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (event.patient != null)
                              Text(
                                event.patient!,
                                style: AppTypography.caption(
                                  context,
                                ).copyWith(color: event.conflict ? colors.statusDangerFg : colors.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

DateTime _startOfWeek(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return normalized.subtract(Duration(days: normalized.weekday % 7));
}

List<DateTime?> _monthDays(int year, int month) {
  final first = DateTime(year, month, 1);
  final lastDay = DateTime(year, month + 1, 0).day;
  final cells = <DateTime?>[];
  for (var i = 0; i < first.weekday % 7; i++) {
    cells.add(null);
  }
  for (var d = 1; d <= lastDay; d++) {
    cells.add(DateTime(year, month, d));
  }
  return cells;
}

List<CalendarEvent> _eventsForDay(List<CalendarEvent> events, DateTime day) {
  return events.where((e) => _isSameDay(e.start, day)).toList();
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

List<String> _weekdayLabels(String locale) {
  final format = DateFormat.E(locale);
  final sunday = DateTime(2024, 1, 7);
  return List.generate(7, (i) => format.format(sunday.add(Duration(days: i))));
}

String _formatHour(int hour) {
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
  return '$displayHour:00 $period';
}
