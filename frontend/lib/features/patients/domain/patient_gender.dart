/// Patient gender aligned with PostgreSQL `patient_gender` enum (V1-3).
enum PatientGender {
  male,
  female,
  other,
  unknown;

  static PatientGender? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'male' => PatientGender.male,
      'female' => PatientGender.female,
      'other' => PatientGender.other,
      'unknown' => PatientGender.unknown,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    PatientGender.male => 'male',
    PatientGender.female => 'female',
    PatientGender.other => 'other',
    PatientGender.unknown => 'unknown',
  };
}
