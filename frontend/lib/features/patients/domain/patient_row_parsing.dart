/// Shared JSON parsing helpers for patient domain models (V1-3).
DateTime? parsePatientDate(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return DateTime.utc(value.year, value.month, value.day);
  }
  final text = value.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null) {
    return null;
  }
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

DateTime? parsePatientDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  final text = value.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}

String? optionalPatientString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
