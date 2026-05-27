/// Appointment type aligned with PostgreSQL `appointment_type` enum (V1-4).
enum AppointmentType {
  planned,
  walkIn;

  static AppointmentType? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'planned' => AppointmentType.planned,
      'walk_in' => AppointmentType.walkIn,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    AppointmentType.planned => 'planned',
    AppointmentType.walkIn => 'walk_in',
  };

  String get label => switch (this) {
    AppointmentType.planned => 'Planned',
    AppointmentType.walkIn => 'Walk-in',
  };
}
