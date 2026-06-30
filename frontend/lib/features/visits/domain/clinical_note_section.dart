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

  String get hint => switch (this) {
    complaint => "The patient's main reason for the visit.",
    examination => 'Physical examination findings.',
    diagnosis => 'Clinical assessment or diagnosis.',
    plan => 'Treatment plan, follow-up instructions, and patient advice.',
    _ => '',
  };

  bool get hasHint => hint.isNotEmpty;
}
