import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/visits/domain/soap_note.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:flutter/foundation.dart';

/// Full visit profile for documentation and detail flows (`get_visit`, V1-5).
@immutable
class VisitDetail {
  const VisitDetail({
    required this.id,
    required this.branchId,
    required this.appointmentId,
    required this.patientId,
    required this.doctorId,
    required this.doctorName,
    required this.visitDate,
    required this.status,
    this.soap,
    this.treatmentPlans = const [],
    this.attachments = const [],
  });

  final String id;
  final String branchId;
  final String appointmentId;
  final String patientId;
  final String doctorId;
  final String doctorName;
  final DateTime visitDate;
  final VisitStatus status;
  final SoapNote? soap;
  final List<TreatmentPlanItem> treatmentPlans;
  final List<VisitAttachmentItem> attachments;

  static VisitDetail? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final branchId = row['branch_id']?.toString();
    final appointmentId = row['appointment_id']?.toString();
    final patientId = row['patient_id']?.toString();
    final doctorId = row['doctor_id']?.toString();
    final doctorName = row['doctor_name']?.toString().trim();
    final visitDate = parseVisitDate(row['visit_date']);
    final status = VisitStatus.tryParse(row['status']?.toString());

    if (id == null ||
        id.isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
        appointmentId == null ||
        appointmentId.isEmpty ||
        patientId == null ||
        patientId.isEmpty ||
        doctorId == null ||
        doctorId.isEmpty ||
        doctorName == null ||
        doctorName.isEmpty ||
        visitDate == null ||
        status == null) {
      return null;
    }

    SoapNote? soap;
    final soapRaw = row['soap'];
    if (soapRaw is Map<String, dynamic>) {
      soap = SoapNote.fromRow(soapRaw);
    } else if (soapRaw is Map) {
      soap = SoapNote.fromRow(Map<String, dynamic>.from(soapRaw));
    }

    final treatmentPlans = _parseTreatmentPlans(row['treatment_plans'], visitId: id, patientId: patientId);
    final attachments = _parseAttachments(row['attachments']);

    return VisitDetail(
      id: id,
      branchId: branchId,
      appointmentId: appointmentId,
      patientId: patientId,
      doctorId: doctorId,
      doctorName: doctorName,
      visitDate: visitDate,
      status: status,
      soap: soap,
      treatmentPlans: treatmentPlans,
      attachments: attachments,
    );
  }

  static List<TreatmentPlanItem> _parseTreatmentPlans(
    Object? raw, {
    required String visitId,
    required String patientId,
  }) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          ?TreatmentPlanItem.fromRow(item, visitId: visitId, patientId: patientId)
        else if (item is Map)
          ?TreatmentPlanItem.fromRow(Map<String, dynamic>.from(item), visitId: visitId, patientId: patientId),
    ].whereType<TreatmentPlanItem>().toList(growable: false);
  }

  static List<VisitAttachmentItem> _parseAttachments(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          ?VisitAttachmentItem.fromRow(item)
        else if (item is Map)
          ?VisitAttachmentItem.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<VisitAttachmentItem>().toList(growable: false);
  }

  VisitDetail copyWith({
    String? id,
    String? branchId,
    String? appointmentId,
    String? patientId,
    String? doctorId,
    String? doctorName,
    DateTime? visitDate,
    VisitStatus? status,
    Object? soap = copyWithSentinel,
    List<TreatmentPlanItem>? treatmentPlans,
    List<VisitAttachmentItem>? attachments,
  }) {
    return VisitDetail(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      appointmentId: appointmentId ?? this.appointmentId,
      patientId: patientId ?? this.patientId,
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      visitDate: visitDate ?? this.visitDate,
      status: status ?? this.status,
      soap: identical(soap, copyWithSentinel) ? this.soap : soap as SoapNote?,
      treatmentPlans: treatmentPlans ?? this.treatmentPlans,
      attachments: attachments ?? this.attachments,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VisitDetail &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            branchId == other.branchId &&
            appointmentId == other.appointmentId &&
            patientId == other.patientId &&
            doctorId == other.doctorId &&
            doctorName == other.doctorName &&
            visitDate == other.visitDate &&
            status == other.status &&
            soap == other.soap &&
            listEquals(treatmentPlans, other.treatmentPlans) &&
            listEquals(attachments, other.attachments);
  }

  @override
  int get hashCode => Object.hash(
    id,
    branchId,
    appointmentId,
    patientId,
    doctorId,
    doctorName,
    visitDate,
    status,
    soap,
    Object.hashAll(treatmentPlans),
    Object.hashAll(attachments),
  );
}
