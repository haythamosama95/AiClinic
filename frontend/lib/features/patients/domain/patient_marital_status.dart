/// Patient marital status aligned with PostgreSQL `patient_marital_status` enum (V1-3).
enum PatientMaritalStatus {
  single,
  married,
  divorced,
  widowed;

  static PatientMaritalStatus? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'single' => PatientMaritalStatus.single,
      'married' => PatientMaritalStatus.married,
      'divorced' => PatientMaritalStatus.divorced,
      'widowed' => PatientMaritalStatus.widowed,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    PatientMaritalStatus.single => 'single',
    PatientMaritalStatus.married => 'married',
    PatientMaritalStatus.divorced => 'divorced',
    PatientMaritalStatus.widowed => 'widowed',
  };

  String get label => switch (this) {
    PatientMaritalStatus.single => 'Single',
    PatientMaritalStatus.married => 'Married',
    PatientMaritalStatus.divorced => 'Divorced',
    PatientMaritalStatus.widowed => 'Widowed',
  };
}
