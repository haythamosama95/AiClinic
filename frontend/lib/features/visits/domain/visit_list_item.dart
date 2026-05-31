import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:flutter/foundation.dart';

/// Visit row for patient history lists (`list_patient_visits`, V1-5).
@immutable
class VisitListItem {
  const VisitListItem({
    required this.id,
    required this.visitDate,
    required this.doctorName,
    required this.status,
    required this.branchName,
  });

  final String id;
  final DateTime visitDate;
  final String doctorName;
  final VisitStatus status;
  final String branchName;

  static VisitListItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final visitDate = parseVisitDate(row['visit_date']);
    final doctorName = row['doctor_name']?.toString().trim();
    final status = VisitStatus.tryParse(row['status']?.toString());
    final branchName = row['branch_name']?.toString().trim();

    if (id == null ||
        id.isEmpty ||
        visitDate == null ||
        doctorName == null ||
        doctorName.isEmpty ||
        status == null ||
        branchName == null ||
        branchName.isEmpty) {
      return null;
    }

    return VisitListItem(id: id, visitDate: visitDate, doctorName: doctorName, status: status, branchName: branchName);
  }

  VisitListItem copyWith({
    String? id,
    DateTime? visitDate,
    String? doctorName,
    VisitStatus? status,
    String? branchName,
  }) {
    return VisitListItem(
      id: id ?? this.id,
      visitDate: visitDate ?? this.visitDate,
      doctorName: doctorName ?? this.doctorName,
      status: status ?? this.status,
      branchName: branchName ?? this.branchName,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VisitListItem &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            visitDate == other.visitDate &&
            doctorName == other.doctorName &&
            status == other.status &&
            branchName == other.branchName;
  }

  @override
  int get hashCode => Object.hash(id, visitDate, doctorName, status, branchName);
}
