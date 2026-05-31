import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Treatment plan line item linked to a visit (V1-5).
@immutable
class TreatmentPlanItem {
  const TreatmentPlanItem({
    required this.id,
    required this.visitId,
    required this.patientId,
    required this.medicationName,
    this.dosage,
    this.frequency,
    this.startDate,
    this.endDate,
    this.notes,
  });

  final String id;
  final String visitId;
  final String patientId;
  final String medicationName;
  final String? dosage;
  final String? frequency;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? notes;

  static TreatmentPlanItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final visitId = row['visit_id']?.toString();
    final patientId = row['patient_id']?.toString();
    final medicationName = row['medication_name']?.toString().trim();

    if (id == null ||
        id.isEmpty ||
        visitId == null ||
        visitId.isEmpty ||
        patientId == null ||
        patientId.isEmpty ||
        medicationName == null ||
        medicationName.isEmpty) {
      return null;
    }

    return TreatmentPlanItem(
      id: id,
      visitId: visitId,
      patientId: patientId,
      medicationName: medicationName,
      dosage: optionalVisitString(row['dosage']),
      frequency: optionalVisitString(row['frequency']),
      startDate: parseVisitDate(row['start_date']),
      endDate: parseVisitDate(row['end_date']),
      notes: optionalVisitString(row['notes']),
    );
  }

  TreatmentPlanItem copyWith({
    String? id,
    String? visitId,
    String? patientId,
    String? medicationName,
    Object? dosage = copyWithSentinel,
    Object? frequency = copyWithSentinel,
    Object? startDate = copyWithSentinel,
    Object? endDate = copyWithSentinel,
    Object? notes = copyWithSentinel,
  }) {
    return TreatmentPlanItem(
      id: id ?? this.id,
      visitId: visitId ?? this.visitId,
      patientId: patientId ?? this.patientId,
      medicationName: medicationName ?? this.medicationName,
      dosage: identical(dosage, copyWithSentinel) ? this.dosage : dosage as String?,
      frequency: identical(frequency, copyWithSentinel) ? this.frequency : frequency as String?,
      startDate: identical(startDate, copyWithSentinel) ? this.startDate : startDate as DateTime?,
      endDate: identical(endDate, copyWithSentinel) ? this.endDate : endDate as DateTime?,
      notes: identical(notes, copyWithSentinel) ? this.notes : notes as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TreatmentPlanItem &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            visitId == other.visitId &&
            patientId == other.patientId &&
            medicationName == other.medicationName &&
            dosage == other.dosage &&
            frequency == other.frequency &&
            startDate == other.startDate &&
            endDate == other.endDate &&
            notes == other.notes;
  }

  @override
  int get hashCode => Object.hash(id, visitId, patientId, medicationName, dosage, frequency, startDate, endDate, notes);
}
