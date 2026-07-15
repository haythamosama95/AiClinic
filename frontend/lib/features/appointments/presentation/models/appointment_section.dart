import 'package:flutter/material.dart';

/// Appointments hub sub-navigation tab identifiers.
enum AppointmentSection {
  hub('hub', 'Hub', Icons.dashboard_outlined),
  queue('queue', 'Queue', Icons.queue_outlined),
  calendar('calendar', 'Calendar', Icons.calendar_month_outlined),
  book('book', 'Book', Icons.add_circle_outline);

  const AppointmentSection(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  static AppointmentSection? byId(String id) {
    for (final section in AppointmentSection.values) {
      if (section.id == id) {
        return section;
      }
    }
    return null;
  }
}

const appointmentSections = AppointmentSection.values;
