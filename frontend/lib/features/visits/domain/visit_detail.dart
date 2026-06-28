import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:flutter/foundation.dart';

/// Full visit profile for documentation and detail flows (`get_visit`, 013).
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
    this.updatedAt,
    this.documentation,
    this.vitalSigns = const [],
    this.investigations = const [],
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
  final DateTime? updatedAt;
  final VisitClinicalNote? documentation;
  final List<VisitVitalSign> vitalSigns;
  final List<VisitInvestigation> investigations;
  final List<TreatmentPlanItem> treatmentPlans;
  final List<VisitAttachmentItem> attachments;

  static VisitDetail? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final branchId = row['branch_id']?.toString();
    final appointmentId = row['appointment_id']?.toString();
    final patientId = row['patient_id']?.toString();
    final doctorId = row['doctor_id']?.toString();
    final doctorNameRaw = row['doctor_name']?.toString().trim();
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
        visitDate == null ||
        status == null) {
      return null;
    }

    final doctorName = doctorNameRaw == null || doctorNameRaw.isEmpty ? 'Unknown doctor' : doctorNameRaw;

    VisitClinicalNote? documentation;
    final documentationRaw = row['documentation'];
    if (documentationRaw is Map<String, dynamic>) {
      documentation = VisitClinicalNote.fromRow(documentationRaw);
    } else if (documentationRaw is Map) {
      documentation = VisitClinicalNote.fromRow(Map<String, dynamic>.from(documentationRaw));
    }

    return VisitDetail(
      id: id,
      branchId: branchId,
      appointmentId: appointmentId,
      patientId: patientId,
      doctorId: doctorId,
      doctorName: doctorName,
      visitDate: visitDate,
      status: status,
      updatedAt: parseVisitDateTime(row['updated_at']),
      documentation: documentation,
      vitalSigns: _parseVitalSigns(row['vital_signs']),
      investigations: _parseInvestigations(row['investigations']),
      treatmentPlans: _parseTreatmentPlans(row['treatment_plans'], visitId: id, patientId: patientId),
      attachments: _parseAttachments(row['attachments']),
    );
  }

  static List<VisitVitalSign> _parseVitalSigns(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          ?VisitVitalSign.fromRow(item)
        else if (item is Map)
          ?VisitVitalSign.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<VisitVitalSign>().toList(growable: false);
  }

  static List<VisitInvestigation> _parseInvestigations(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          ?VisitInvestigation.fromRow(item)
        else if (item is Map)
          ?VisitInvestigation.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<VisitInvestigation>().toList(growable: false);
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
    Object? updatedAt = copyWithSentinel,
    Object? documentation = copyWithSentinel,
    List<VisitVitalSign>? vitalSigns,
    List<VisitInvestigation>? investigations,
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
      updatedAt: identical(updatedAt, copyWithSentinel) ? this.updatedAt : updatedAt as DateTime?,
      documentation: identical(documentation, copyWithSentinel)
          ? this.documentation
          : documentation as VisitClinicalNote?,
      vitalSigns: vitalSigns ?? this.vitalSigns,
      investigations: investigations ?? this.investigations,
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
            updatedAt == other.updatedAt &&
            documentation == other.documentation &&
            listEquals(vitalSigns, other.vitalSigns) &&
            listEquals(investigations, other.investigations) &&
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
    updatedAt,
    documentation,
    Object.hashAll(vitalSigns),
    Object.hashAll(investigations),
    Object.hashAll(treatmentPlans),
    Object.hashAll(attachments),
  );
}
