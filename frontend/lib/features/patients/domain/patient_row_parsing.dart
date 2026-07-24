// Shared JSON parsing helpers for patient domain models (V1-3).

/// Normalizes a calendar date to UTC midnight (year/month/day only).
DateTime normalizePatientDate(DateTime date) => DateTime.utc(date.year, date.month, date.day);

/// Serializes a patient calendar date as `YYYY-MM-DD` without timezone shift.
String formatPatientDateWire(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

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

/// Parses MRN from RPC row keys (`mrn` preferred, `patient_mrn` fallback).
String? parsePatientMrn(Map<String, dynamic> row) {
  return optionalPatientString(row['mrn'] ?? row['patient_mrn']);
}
