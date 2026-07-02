/// Organization-wide service availability (Service Catalog 015).
enum GlobalStatus {
  active,
  inactive;

  static GlobalStatus? tryParse(String? raw) {
    if (raw == null) {
      return null;
    }
    final normalized = raw.trim().toLowerCase();
    return switch (normalized) {
      'active' => GlobalStatus.active,
      'inactive' => GlobalStatus.inactive,
      _ => null,
    };
  }

  String get wireValue => name;
}
