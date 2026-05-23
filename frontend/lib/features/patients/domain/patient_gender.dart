/// Patient gender aligned with PostgreSQL `patient_gender` enum (V1-3).
enum PatientGender {
  male,
  female;

  static PatientGender? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'male' => PatientGender.male,
      'female' => PatientGender.female,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    PatientGender.male => 'male',
    PatientGender.female => 'female',
  };
}
