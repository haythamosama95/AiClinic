import 'package:clock/clock.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/features/patients/domain/patient_gender.dart';

/// Shared display helpers for patient list and detail views.
abstract final class PatientPresentationFormatting {
  static final date = DateFormat.yMMMd();
  static final dateTime = DateFormat('MMM d, y · h:mm a');

  static String displayId(String id) {
    return id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
  }

  static int? ageYears(DateTime? dateOfBirth) {
    if (dateOfBirth == null) {
      return null;
    }
    final now = clock.now();
    final today = DateTime(now.year, now.month, now.day);
    final birthDate = DateTime(dateOfBirth.year, dateOfBirth.month, dateOfBirth.day);
    if (birthDate.isAfter(today)) {
      return null;
    }
    var years = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
      years--;
    }
    return years;
  }

  static String ageGenderLabel({int? age, PatientGender? gender}) {
    final agePart = age?.toString();
    final genderPart = gender?.label;
    if (agePart != null && genderPart != null) {
      return '$agePart, $genderPart';
    }
    if (agePart != null) {
      return agePart;
    }
    if (genderPart != null) {
      return genderPart;
    }
    return '—';
  }

  static String dateOfBirthLabel(DateTime? dateOfBirth) {
    if (dateOfBirth == null) {
      return '—';
    }
    final age = ageYears(dateOfBirth);
    final formatted = date.format(dateOfBirth);
    if (age == null) {
      return formatted;
    }
    return '$formatted ($age yrs)';
  }

  static String orDash(String? value) => value == null || value.trim().isEmpty ? '—' : value;
}
