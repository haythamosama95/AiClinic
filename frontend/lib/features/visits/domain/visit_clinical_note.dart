import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

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

  static bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}
