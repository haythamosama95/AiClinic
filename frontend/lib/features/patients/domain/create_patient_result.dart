import 'package:flutter/foundation.dart';

/// Result of a successful patient creation RPC (patient id + assigned MRN).
@immutable
class CreatePatientResult {
  const CreatePatientResult({required this.patientId, required this.mrn});

  final String patientId;
  final String mrn;

  factory CreatePatientResult.fromJson(Map<String, dynamic> json) {
    final patientId = json['patient_id']?.toString();
    final mrn = json['mrn']?.toString();
    if (patientId == null || patientId.isEmpty) {
      throw const FormatException('create_patient result missing patient_id');
    }
    if (mrn == null || mrn.isEmpty) {
      throw const FormatException('create_patient result missing mrn');
    }
    return CreatePatientResult(patientId: patientId, mrn: mrn);
  }

  CreatePatientResult copyWith({String? patientId, String? mrn}) {
    return CreatePatientResult(
      patientId: patientId ?? this.patientId,
      mrn: mrn ?? this.mrn,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CreatePatientResult &&
            runtimeType == other.runtimeType &&
            patientId == other.patientId &&
            mrn == other.mrn;
  }

  @override
  int get hashCode => Object.hash(patientId, mrn);
}
