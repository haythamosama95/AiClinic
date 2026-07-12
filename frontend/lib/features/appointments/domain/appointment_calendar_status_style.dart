import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Theme-aware fill, border, and text tokens for a calendar appointment status.
@immutable
class AppointmentCalendarStatusStyle {
  const AppointmentCalendarStatusStyle({
    required this.accent,
    required this.gradientStart,
    required this.gradientEnd,
    required this.border,
    required this.text,
    required this.textMuted,
  });

  /// Accent used for Syncfusion color fields and the encounter strip rail.
  final Color accent;

  final Color gradientStart;
  final Color gradientEnd;
  final Color border;
  final Color text;
  final Color textMuted;
}

/// Pearlescent, clinic-chic status palette for the appointment calendar.
abstract final class AppointmentCalendarStatusPalette {
  static AppointmentCalendarStatusStyle styleFor(AppointmentStatus status, Brightness brightness) {
    return switch (brightness) {
      Brightness.dark => _darkStyle(status),
      Brightness.light => _lightStyle(status),
    };
  }

  static AppointmentCalendarStatusStyle filteredOutStyle(Brightness brightness) {
    return brightness == Brightness.dark ? _filteredOutDark : _filteredOutLight;
  }

  static const _filteredOutLight = AppointmentCalendarStatusStyle(
    accent: Color(0xFF9CA3AF),
    gradientStart: Color(0xFFF0F1F3),
    gradientEnd: Color(0xFFDDE0E4),
    border: Color(0xFFB8BFC8),
    text: Color(0xFF6B7280),
    textMuted: Color(0xFF9CA3AF),
  );

  static const _filteredOutDark = AppointmentCalendarStatusStyle(
    accent: Color(0xFF6B7280),
    gradientStart: Color(0xFF2A2D32),
    gradientEnd: Color(0xFF1E2024),
    border: Color(0xFF505560),
    text: Color(0xFF9CA3AF),
    textMuted: Color(0xFF6B7280),
  );

  static AppointmentCalendarStatusStyle _lightStyle(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => const AppointmentCalendarStatusStyle(
        accent: Color(0xFF6E8499),
        gradientStart: Color(0xFFE4EBF2),
        gradientEnd: Color(0xFFC8D4E0),
        border: Color(0xFF8FA3B8),
        text: Color(0xFF2C3E50),
        textMuted: Color(0xFF4A5D70),
      ),
      AppointmentStatus.confirmed => const AppointmentCalendarStatusStyle(
        accent: Color(0xFF5B6FD8),
        gradientStart: Color(0xFFECEFFD),
        gradientEnd: Color(0xFFC5CEF5),
        border: Color(0xFF6F82E0),
        text: Color(0xFF1F2B5C),
        textMuted: Color(0xFF3D4D7A),
      ),
      AppointmentStatus.checkedIn => const AppointmentCalendarStatusStyle(
        accent: Color(0xFFC4A035),
        gradientStart: Color(0xFFFBF6E8),
        gradientEnd: Color(0xFFEDD9A3),
        border: Color(0xFFD4B84A),
        text: Color(0xFF4A3D18),
        textMuted: Color(0xFF6B5A28),
      ),
      AppointmentStatus.inProgress => const AppointmentCalendarStatusStyle(
        accent: Color(0xFFD96B52),
        gradientStart: Color(0xFFFDEEEA),
        gradientEnd: Color(0xFFF4C4B8),
        border: Color(0xFFE08068),
        text: Color(0xFF5C3028),
        textMuted: Color(0xFF7A4A40),
      ),
      AppointmentStatus.completed => const AppointmentCalendarStatusStyle(
        accent: Color(0xFF3D9A72),
        gradientStart: Color(0xFFE6F5ED),
        gradientEnd: Color(0xFFB5DFC9),
        border: Color(0xFF4AAD82),
        text: Color(0xFF1A3D2C),
        textMuted: Color(0xFF2E5A48),
      ),
      AppointmentStatus.cancelled => const AppointmentCalendarStatusStyle(
        accent: Color(0xFFC05868),
        gradientStart: Color(0xFFFAECEE),
        gradientEnd: Color(0xFFEEC4CA),
        border: Color(0xFFD06A78),
        text: Color(0xFF4A2228),
        textMuted: Color(0xFF6E3840),
      ),
      AppointmentStatus.noShow => const AppointmentCalendarStatusStyle(
        accent: Color(0xFF8A7B9C),
        gradientStart: Color(0xFFF0EDF4),
        gradientEnd: Color(0xFFD5CEE0),
        border: Color(0xFF9E90AE),
        text: Color(0xFF36304A),
        textMuted: Color(0xFF524A62),
      ),
      AppointmentStatus.unknown => const AppointmentCalendarStatusStyle(
        accent: Color(0xFF7A8494),
        gradientStart: Color(0xFFECEEF2),
        gradientEnd: Color(0xFFD0D5DC),
        border: Color(0xFF9AA3B0),
        text: Color(0xFF2E3440),
        textMuted: Color(0xFF4A5260),
      ),
    };
  }

  static AppointmentCalendarStatusStyle _darkStyle(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => const AppointmentCalendarStatusStyle(
        accent: Color(0xFF92A8BD),
        gradientStart: Color(0xFF2C3540),
        gradientEnd: Color(0xFF1E242C),
        border: Color(0xFF6E8298),
        text: Color(0xFFE4EBF2),
        textMuted: Color(0xFFB8C5D0),
      ),
      AppointmentStatus.confirmed => const AppointmentCalendarStatusStyle(
        accent: Color(0xFF8494F0),
        gradientStart: Color(0xFF222845),
        gradientEnd: Color(0xFF181D35),
        border: Color(0xFF6878D8),
        text: Color(0xFFEAEDFF),
        textMuted: Color(0xFFB8C0E8),
      ),
      AppointmentStatus.checkedIn => const AppointmentCalendarStatusStyle(
        accent: Color(0xFFDBB84A),
        gradientStart: Color(0xFF383020),
        gradientEnd: Color(0xFF282018),
        border: Color(0xFFB89838),
        text: Color(0xFFFFF8E6),
        textMuted: Color(0xFFE8D8A8),
      ),
      AppointmentStatus.inProgress => const AppointmentCalendarStatusStyle(
        accent: Color(0xFFE88870),
        gradientStart: Color(0xFF382820),
        gradientEnd: Color(0xFF281C18),
        border: Color(0xFFD07058),
        text: Color(0xFFFFEDE8),
        textMuted: Color(0xFFE8C0B4),
      ),
      AppointmentStatus.completed => const AppointmentCalendarStatusStyle(
        accent: Color(0xFF58B88A),
        gradientStart: Color(0xFF1E3028),
        gradientEnd: Color(0xFF142420),
        border: Color(0xFF48A078),
        text: Color(0xFFE0F5EA),
        textMuted: Color(0xFFB0D8C4),
      ),
      AppointmentStatus.cancelled => const AppointmentCalendarStatusStyle(
        accent: Color(0xFFD87080),
        gradientStart: Color(0xFF382028),
        gradientEnd: Color(0xFF281820),
        border: Color(0xFFC05868),
        text: Color(0xFFFFE8EC),
        textMuted: Color(0xFFE8B8C0),
      ),
      AppointmentStatus.noShow => const AppointmentCalendarStatusStyle(
        accent: Color(0xFFA898B8),
        gradientStart: Color(0xFF302830),
        gradientEnd: Color(0xFF201820),
        border: Color(0xFF887898),
        text: Color(0xFFEDE8F2),
        textMuted: Color(0xFFC8BCD8),
      ),
      AppointmentStatus.unknown => const AppointmentCalendarStatusStyle(
        accent: Color(0xFF8A92A0),
        gradientStart: Color(0xFF2A2E34),
        gradientEnd: Color(0xFF1E2126),
        border: Color(0xFF626A78),
        text: Color(0xFFE8EAEE),
        textMuted: Color(0xFFB0B8C4),
      ),
    };
  }
}
