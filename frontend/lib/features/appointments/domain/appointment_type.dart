/// Appointment type aligned with PostgreSQL `appointment_type` enum (V1-4).
enum AppointmentType {
  planned,
  unknown;

  static AppointmentType? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'planned' => AppointmentType.planned,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    AppointmentType.planned => 'planned',
    AppointmentType.unknown => 'unknown',
  };

  String get label => switch (this) {
    AppointmentType.planned => 'Planned',
    AppointmentType.unknown => 'Unknown',
  };
}
