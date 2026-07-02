import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Maximum characters per clinical note section (matches backend validation).
const kMaxClinicalSectionLength = 10000;

/// User-facing error when any clinical section exceeds [kMaxClinicalSectionLength], or null if valid.
String? clinicalSectionLengthError({
  required String complaint,
  required String history,
  required String examination,
  required String diagnosis,
  required String plan,
}) {
  if (complaint.length > kMaxClinicalSectionLength ||
      history.length > kMaxClinicalSectionLength ||
      examination.length > kMaxClinicalSectionLength ||
      diagnosis.length > kMaxClinicalSectionLength ||
      plan.length > kMaxClinicalSectionLength) {
    return 'Each clinical note section must be 10,000 characters or fewer.';
  }
  return null;
}

/// Clinical note sections for a visit (013 redesign).
@immutable
class VisitClinicalNote {
  const VisitClinicalNote({this.complaint, this.history, this.examination, this.diagnosis, this.plan, this.updatedAt});

  final String? complaint;
  final String? history;
  final String? examination;
  final String? diagnosis;
  final String? plan;
  final DateTime? updatedAt;

  static VisitClinicalNote? fromRow(Map<String, dynamic> row) {
    return VisitClinicalNote(
      complaint: optionalVisitString(row['complaint']),
      history: optionalVisitString(row['history']),
      examination: optionalVisitString(row['examination']),
      diagnosis: optionalVisitString(row['diagnosis']),
      plan: optionalVisitString(row['plan']),
      updatedAt: parseVisitDateTime(row['updated_at']),
    );
  }

  bool get hasContent =>
      _hasText(complaint) || _hasText(history) || _hasText(examination) || _hasText(diagnosis) || _hasText(plan);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VisitClinicalNote &&
            runtimeType == other.runtimeType &&
            complaint == other.complaint &&
            history == other.history &&
            examination == other.examination &&
            diagnosis == other.diagnosis &&
            plan == other.plan &&
            updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(complaint, history, examination, diagnosis, plan, updatedAt);

  static bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}
