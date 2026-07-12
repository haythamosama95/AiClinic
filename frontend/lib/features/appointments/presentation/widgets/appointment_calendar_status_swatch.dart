import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';

/// Shared status fill styling for calendar tiles and the color legend.
abstract final class AppointmentCalendarStatusSwatch {
  static const fillOpacity = 0.9;

  static BoxDecoration decoration(Color statusColor, {double radius = AppRadius.md}) {
    return BoxDecoration(
      color: statusColor.withValues(alpha: fillOpacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: statusColor),
    );
  }

  static Color textOn(Color statusColor) {
    return ThemeData.estimateBrightnessForColor(statusColor) == Brightness.dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF1F2937);
  }

  static Color textOnMuted(Color statusColor) {
    return textOn(statusColor).withValues(alpha: 0.82);
  }
}
