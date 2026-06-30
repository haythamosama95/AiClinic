/// Subset of the five-section clinical note used by encounter phase canvases (014).
enum ClinicalNoteSection {
  complaint,
  history,
  examination,
  diagnosis,
  plan;

  String get abbr => switch (this) {
    complaint => 'C',
    history => 'H',
    examination => 'E',
    diagnosis => 'D',
    plan => 'P',
  };

  String get label => switch (this) {
    complaint => 'Complaint',
    history => 'History',
    examination => 'Examination',
    diagnosis => 'Diagnosis',
    plan => 'Plan',
  };
}
