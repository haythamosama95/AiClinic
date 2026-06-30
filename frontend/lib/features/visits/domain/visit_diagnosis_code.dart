import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Org-scoped diagnosis catalog row (`search_diagnosis_codes`, 014 US7).
@immutable
class DiagnosisCatalogItem {
  const DiagnosisCatalogItem({required this.id, required this.name, this.code});

  final String id;
  final String name;
  final String? code;

  String get displayLabel {
    final trimmedCode = code?.trim();
    if (trimmedCode == null || trimmedCode.isEmpty) {
      return name;
    }
    return '$trimmedCode — $name';
  }

  static DiagnosisCatalogItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }
    return DiagnosisCatalogItem(id: id, name: name, code: optionalVisitString(row['code']));
  }
}

/// Visit-level coded diagnosis line (`get_visit.diagnosis_codes`, 014 US7).
@immutable
class VisitDiagnosisCode {
  const VisitDiagnosisCode({required this.id, required this.label, this.code, this.diagnosisCodeId});

  final String id;
  final String label;
  final String? code;
  final String? diagnosisCodeId;

  String get displayLabel {
    final trimmedCode = code?.trim();
    if (trimmedCode == null || trimmedCode.isEmpty) {
      return label;
    }
    return '$trimmedCode — $label';
  }

  static VisitDiagnosisCode? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final label = row['label']?.toString().trim();
    if (id == null || id.isEmpty || label == null || label.isEmpty) {
      return null;
    }
    return VisitDiagnosisCode(
      id: id,
      label: label,
      code: optionalVisitString(row['code']),
      diagnosisCodeId: optionalVisitString(row['diagnosis_code_id']),
    );
  }
}
