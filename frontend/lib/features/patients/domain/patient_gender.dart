/// Patient gender aligned with PostgreSQL `patient_gender` enum (V1-3).
enum PatientGender {
  male,
  female,
  other,
  preferNotToSay,
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
      'prefer_not_to_say' => PatientGender.preferNotToSay,
      'unknown' => PatientGender.unknown,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    PatientGender.male => 'male',
    PatientGender.female => 'female',
    PatientGender.other => 'other',
    PatientGender.preferNotToSay => 'prefer_not_to_say',
    PatientGender.unknown => 'unknown',
  };

  String get label => switch (this) {
    PatientGender.male => 'Male',
    PatientGender.female => 'Female',
    PatientGender.other => 'Other',
    PatientGender.preferNotToSay => 'Prefer not to say',
    PatientGender.unknown => 'Unknown',
  };
}
