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

  /// Whether [target] is an allowed next status from [this] (V1-4 lifecycle matrix).
  bool canTransitionTo(AppointmentStatus target) {
    if (isTerminal) {
      return false;
    }

    return switch (this) {
      AppointmentStatus.scheduled =>
        target == AppointmentStatus.confirmed ||
            target == AppointmentStatus.cancelled ||
            target == AppointmentStatus.noShow,
      AppointmentStatus.confirmed =>
        target == AppointmentStatus.checkedIn ||
            target == AppointmentStatus.cancelled ||
            target == AppointmentStatus.noShow,
      AppointmentStatus.checkedIn =>
        target == AppointmentStatus.inProgress ||
            target == AppointmentStatus.cancelled ||
            target == AppointmentStatus.noShow,
      AppointmentStatus.inProgress => target == AppointmentStatus.completed,
      _ => false,
    };
  }
}
