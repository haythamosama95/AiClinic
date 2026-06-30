import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Vital sign line on a visit.
@immutable
class VisitVitalSign {
  const VisitVitalSign({
    required this.id,
    required this.name,
    required this.value,
    this.unit,
    this.predefinedVitalSignId,
    this.measuredAt,
  });

  final String id;
  final String name;
  final String value;
  final String? unit;
  final String? predefinedVitalSignId;
  final DateTime? measuredAt;

  static VisitVitalSign? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();
    final value = row['value']?.toString().trim();

    if (id == null || id.isEmpty || name == null || name.isEmpty || value == null || value.isEmpty) {
      return null;
    }

    return VisitVitalSign(
      id: id,
      name: name,
      value: value,
      unit: optionalVisitString(row['unit']),
      predefinedVitalSignId: row['predefined_vital_sign_id']?.toString(),
      measuredAt: parseVisitDateTime(row['measured_at']),
    );
  }
}
