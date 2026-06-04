import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Maximum characters per SOAP section (matches backend `save_soap_note` validation).
const kMaxSoapSectionLength = 10000;

/// User-facing error when any SOAP section exceeds [kMaxSoapSectionLength], or null if valid.
String? soapSectionLengthError({
  required String subjective,
  required String objective,
  required String assessment,
  required String plan,
}) {
  if (subjective.length > kMaxSoapSectionLength ||
      objective.length > kMaxSoapSectionLength ||
      assessment.length > kMaxSoapSectionLength ||
      plan.length > kMaxSoapSectionLength) {
    return 'Each SOAP section must be 10,000 characters or fewer.';
  }
  return null;
}

/// SOAP note content for a visit (`soap_notes` table, V1-5).
@immutable
class SoapNote {
  const SoapNote({
    this.subjective,
    this.objective,
    this.assessment,
    this.plan,
    this.specialtyFormJson = const {},
    required this.updatedAt,
  });

  final String? subjective;
  final String? objective;
  final String? assessment;
  final String? plan;
  final Map<String, dynamic> specialtyFormJson;
  final DateTime updatedAt;

  /// True when at least one SOAP section has non-empty content.
  bool get hasAnySection {
    bool nonEmpty(String? value) => value?.trim().isNotEmpty == true;
    return nonEmpty(subjective) || nonEmpty(objective) || nonEmpty(assessment) || nonEmpty(plan);
  }

  static SoapNote? fromRow(Map<String, dynamic> row) {
    final updatedAt = parseVisitDateTime(row['updated_at']);
    if (updatedAt == null) {
      return null;
    }

    return SoapNote(
      subjective: optionalVisitString(row['subjective']),
      objective: optionalVisitString(row['objective']),
      assessment: optionalVisitString(row['assessment']),
      plan: optionalVisitString(row['plan']),
      specialtyFormJson: parseVisitJsonObject(row['specialty_form_json']),
      updatedAt: updatedAt,
    );
  }

  SoapNote copyWith({
    Object? subjective = copyWithSentinel,
    Object? objective = copyWithSentinel,
    Object? assessment = copyWithSentinel,
    Object? plan = copyWithSentinel,
    Map<String, dynamic>? specialtyFormJson,
    DateTime? updatedAt,
  }) {
    return SoapNote(
      subjective: identical(subjective, copyWithSentinel) ? this.subjective : subjective as String?,
      objective: identical(objective, copyWithSentinel) ? this.objective : objective as String?,
      assessment: identical(assessment, copyWithSentinel) ? this.assessment : assessment as String?,
      plan: identical(plan, copyWithSentinel) ? this.plan : plan as String?,
      specialtyFormJson: specialtyFormJson ?? this.specialtyFormJson,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SoapNote &&
            runtimeType == other.runtimeType &&
            subjective == other.subjective &&
            objective == other.objective &&
            assessment == other.assessment &&
            plan == other.plan &&
            mapEquals(specialtyFormJson, other.specialtyFormJson) &&
            updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    subjective,
    objective,
    assessment,
    plan,
    Object.hashAll(specialtyFormJson.entries.map((e) => Object.hash(e.key, e.value))),
    updatedAt,
  );
}
