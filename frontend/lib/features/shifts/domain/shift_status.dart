/// Derived shift status from assignment count and soft-delete (V1-7).
enum ShiftStatus {
  active,
  incomplete,
  cancelled,
  unknown;

  static ShiftStatus? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'active' => ShiftStatus.active,
      'incomplete' => ShiftStatus.incomplete,
      'cancelled' => ShiftStatus.cancelled,
      _ => ShiftStatus.unknown,
    };
  }

  String get wireValue => switch (this) {
    ShiftStatus.active => 'active',
    ShiftStatus.incomplete => 'incomplete',
    ShiftStatus.cancelled => 'cancelled',
    ShiftStatus.unknown => 'unknown',
  };
}
