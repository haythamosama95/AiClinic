/// Appointment status aligned with PostgreSQL `appointment_status` enum (V1-4).
enum AppointmentStatus {
  scheduled,
  confirmed,
  checkedIn,
  inProgress,
  completed,
  cancelled,
  noShow;

  static AppointmentStatus? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'scheduled' => AppointmentStatus.scheduled,
      'confirmed' => AppointmentStatus.confirmed,
      'checked_in' => AppointmentStatus.checkedIn,
      'in_progress' => AppointmentStatus.inProgress,
      'completed' => AppointmentStatus.completed,
      'cancelled' => AppointmentStatus.cancelled,
      'no_show' => AppointmentStatus.noShow,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    AppointmentStatus.scheduled => 'scheduled',
    AppointmentStatus.confirmed => 'confirmed',
    AppointmentStatus.checkedIn => 'checked_in',
    AppointmentStatus.inProgress => 'in_progress',
    AppointmentStatus.completed => 'completed',
    AppointmentStatus.cancelled => 'cancelled',
    AppointmentStatus.noShow => 'no_show',
  };

  String get label => switch (this) {
    AppointmentStatus.scheduled => 'Scheduled',
    AppointmentStatus.confirmed => 'Confirmed',
    AppointmentStatus.checkedIn => 'Checked in',
    AppointmentStatus.inProgress => 'In progress',
    AppointmentStatus.completed => 'Completed',
    AppointmentStatus.cancelled => 'Cancelled',
    AppointmentStatus.noShow => 'No-show',
  };

  /// Terminal statuses cannot transition further (V1-4 lifecycle).
  bool get isTerminal => switch (this) {
    AppointmentStatus.completed => true,
    AppointmentStatus.cancelled => true,
    AppointmentStatus.noShow => true,
    _ => false,
  };
}
