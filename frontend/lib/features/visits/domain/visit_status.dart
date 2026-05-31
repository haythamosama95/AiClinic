/// Visit status aligned with PostgreSQL `visit_status` enum (V1-5).
enum VisitStatus {
  inProgress,
  completed;

  static VisitStatus? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'in_progress' => VisitStatus.inProgress,
      'completed' => VisitStatus.completed,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    VisitStatus.inProgress => 'in_progress',
    VisitStatus.completed => 'completed',
  };

  String get label => switch (this) {
    VisitStatus.inProgress => 'In progress',
    VisitStatus.completed => 'Completed',
  };

  /// Completed visits cannot transition further (V1-5 lifecycle).
  bool get isTerminal => this == VisitStatus.completed;

  /// Whether [target] is an allowed next status from [this].
  bool canTransitionTo(VisitStatus target) {
    if (isTerminal) {
      return false;
    }
    return switch (this) {
      VisitStatus.inProgress => target == VisitStatus.completed,
      VisitStatus.completed => false,
    };
  }
}
