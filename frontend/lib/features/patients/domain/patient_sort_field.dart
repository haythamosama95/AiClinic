/// Sort options for the patients list (server-backed via `search_patients`).
enum PatientSortField { nameAsc, nameDesc, lastVisitAsc, lastVisitDesc }

extension PatientSortFieldWire on PatientSortField {
  String get wireValue => switch (this) {
    PatientSortField.nameAsc => 'name_asc',
    PatientSortField.nameDesc => 'name_desc',
    PatientSortField.lastVisitAsc => 'last_visit_asc',
    PatientSortField.lastVisitDesc => 'last_visit_desc',
  };
}
