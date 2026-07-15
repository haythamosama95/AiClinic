import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_status_style.dart';

/// Shared status fill styling for calendar tiles and the color legend.
abstract final class AppointmentCalendarStatusSwatch {
  static BoxDecoration decoration(AppointmentCalendarStatusStyle style, {double radius = AppRadius.md}) {
    final isDark = ThemeData.estimateBrightnessForColor(style.gradientEnd) == Brightness.dark;

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [style.gradientStart, style.gradientEnd],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: style.border.withValues(alpha: isDark ? 0.45 : 0.5)),
      boxShadow: [
        BoxShadow(
          color: style.accent.withValues(alpha: isDark ? 0.18 : 0.1),
          blurRadius: 6,
          offset: const Offset(0, 1.5),
        ),
      ],
    );
  }

  static Color highlightSheen(Brightness brightness) {
    return brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.28);
  }
}
