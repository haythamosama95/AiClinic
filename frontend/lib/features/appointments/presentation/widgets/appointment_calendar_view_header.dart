import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/components/app_calendar.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_layout.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_geometry.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';

/// Custom day/week column header aligned with the Syncfusion time grid.
class AppointmentCalendarViewHeader extends StatelessWidget {
  const AppointmentCalendarViewHeader({required this.mode, required this.focusDate, required this.colors, super.key});

  final AppointmentCalendarMode mode;
  final DateTime focusDate;
  final AppSemanticColors colors;

  static bool showsFor(AppointmentCalendarMode mode) {
    return mode == AppointmentCalendarMode.day || mode == AppointmentCalendarMode.week;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode == 'ar' ? 'ar-EG' : 'en-GB';
    final weekdayFormat = DateFormat.E(locale);
    final days = AppointmentCalendarLayout.visibleHeaderDays(mode, focusDate);
    final today = DateTime.now();

    return SizedBox(
      height: AppointmentCalendarGeometry.viewHeaderHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: AppointmentCalendarGeometry.timeLabelWidth),
          for (var index = 0; index < days.length; index++)
            Expanded(
              child: AppCalendarDayColumnHeader(
                colors: colors,
                day: days[index],
                weekday: weekdayFormat.format(days[index]),
                isToday: _isSameDay(days[index], today),
                isLast: index == days.length - 1,
                badgeSize: AppointmentCalendarGeometry.viewHeaderBadgeSize,
                verticalPadding: AppointmentCalendarGeometry.viewHeaderVerticalPadding,
              ),
            ),
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
