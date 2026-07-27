/// Last-visit date range filter (server-backed via `search_patients`).
enum PatientLastVisitFilter { any, last30Days, last90Days, over90Days, never }

extension PatientLastVisitFilterWire on PatientLastVisitFilter {
  String get wireValue => switch (this) {
    PatientLastVisitFilter.any => 'any',
    PatientLastVisitFilter.last30Days => 'last_30_days',
    PatientLastVisitFilter.last90Days => 'last_90_days',
    PatientLastVisitFilter.over90Days => 'over_90_days',
    PatientLastVisitFilter.never => 'never',
  };
}
