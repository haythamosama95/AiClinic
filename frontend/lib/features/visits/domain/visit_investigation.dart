import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Investigation line ordered on a visit.
@immutable
class VisitInvestigation {
  const VisitInvestigation({required this.id, required this.name, this.note, this.investigationId});

  final String id;
  final String name;
  final String? note;
  final String? investigationId;

  static VisitInvestigation? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();

    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }

    return VisitInvestigation(
      id: id,
      name: name,
      note: optionalVisitString(row['note']),
      investigationId: row['investigation_id']?.toString(),
    );
  }
}
