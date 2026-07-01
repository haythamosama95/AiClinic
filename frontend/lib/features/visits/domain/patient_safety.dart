import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Known allergy severity values stored in the optional [PatientAllergy.reaction] field.
abstract final class AllergySeverityOptions {
  static const items = <String, String>{
    'Mild': 'Mild',
    'Moderate': 'Moderate',
    'Severe': 'Severe',
    'Life-threatening': 'Life-threatening',
  };
}

/// Patient-level allergy record (014 US6).
@immutable
class PatientAllergy {
  const PatientAllergy({required this.id, required this.substance, this.reaction});

  final String id;
  final String substance;
  final String? reaction;

  static PatientAllergy? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final substance = row['substance']?.toString().trim();
    if (id == null || id.isEmpty || substance == null || substance.isEmpty) {
      return null;
    }
    return PatientAllergy(id: id, substance: substance, reaction: optionalVisitString(row['reaction']));
  }
}

/// Patient-level current/home medication (014 US6).
@immutable
class PatientMedication {
  const PatientMedication({required this.id, required this.name, this.medicationId, this.note});

  final String id;
  final String name;
  final String? medicationId;
  final String? note;

  static PatientMedication? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }
    return PatientMedication(
      id: id,
      name: name,
      medicationId: optionalVisitString(row['medication_id']),
      note: optionalVisitString(row['note']),
    );
  }
}

/// Patient-level chronic condition / problem-list entry (014 US6).
@immutable
class PatientChronicCondition {
  const PatientChronicCondition({required this.id, required this.name, this.note});

  final String id;
  final String name;
  final String? note;

  static PatientChronicCondition? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }
    return PatientChronicCondition(id: id, name: name, note: optionalVisitString(row['note']));
  }
}

/// Single vital from the patient's most recent prior visit (014 US6).
@immutable
class PatientSafetyLastVital {
  const PatientSafetyLastVital({required this.name, required this.value, this.unit, this.measuredAt});

  final String name;
  final String value;
  final String? unit;
  final DateTime? measuredAt;

  static PatientSafetyLastVital? fromRow(Map<String, dynamic> row) {
    final name = row['name']?.toString().trim();
    final value = row['value']?.toString().trim();
    if (name == null || name.isEmpty || value == null || value.isEmpty) {
      return null;
    }
    return PatientSafetyLastVital(
      name: name,
      value: value,
      unit: optionalVisitString(row['unit']),
      measuredAt: parseVisitDateTime(row['measured_at']),
    );
  }
}

/// Last prior-visit vitals block from `get_patient_safety_context`.
@immutable
class PatientSafetyLastVitals {
  const PatientSafetyLastVitals({this.visitId, this.visitDate, this.items = const []});

  final String? visitId;
  final DateTime? visitDate;
  final List<PatientSafetyLastVital> items;

  bool get isEmpty => items.isEmpty;

  static PatientSafetyLastVitals fromRow(Map<String, dynamic>? row) {
    if (row == null) {
      return const PatientSafetyLastVitals();
    }
    final rawItems = row['items'];
    final items = <PatientSafetyLastVital>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          final parsed = PatientSafetyLastVital.fromRow(item);
          if (parsed != null) {
            items.add(parsed);
          }
        } else if (item is Map) {
          final parsed = PatientSafetyLastVital.fromRow(Map<String, dynamic>.from(item));
          if (parsed != null) {
            items.add(parsed);
          }
        }
      }
    }
    return PatientSafetyLastVitals(
      visitId: optionalVisitString(row['visit_id']),
      visitDate: parseVisitDate(row['visit_date']),
      items: items,
    );
  }
}

/// Full patient safety context (`get_patient_safety_context`, 014 US6).
@immutable
class PatientSafetyContext {
  const PatientSafetyContext({
    this.allergies = const [],
    this.currentMedications = const [],
    this.chronicConditions = const [],
    this.lastVitals = const PatientSafetyLastVitals(),
  });

  final List<PatientAllergy> allergies;
  final List<PatientMedication> currentMedications;
  final List<PatientChronicCondition> chronicConditions;
  final PatientSafetyLastVitals lastVitals;

  bool get hasStructuredData =>
      allergies.isNotEmpty || currentMedications.isNotEmpty || chronicConditions.isNotEmpty || !lastVitals.isEmpty;

  static PatientSafetyContext fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return const PatientSafetyContext();
    }
    return PatientSafetyContext(
      allergies: _parseList(data['allergies'], PatientAllergy.fromRow),
      currentMedications: _parseList(data['current_medications'], PatientMedication.fromRow),
      chronicConditions: _parseList(data['chronic_conditions'], PatientChronicCondition.fromRow),
      lastVitals: PatientSafetyLastVitals.fromRow(parseVisitJsonObject(data['last_vitals'])),
    );
  }

  static List<T> _parseList<T>(Object? raw, T? Function(Map<String, dynamic>) parse) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>) ?parse(item) else if (item is Map) ?parse(Map<String, dynamic>.from(item)),
    ].whereType<T>().toList(growable: false);
  }
}
