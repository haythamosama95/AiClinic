import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';

/// Visit medical records RPC wrappers (V1-5).
class VisitRepository with AppRpcInvoker {
  VisitRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260531180000_visit_medical_records.sql';

  @override
  String get rpcLogDomain => 'visits';

  Future<CreateVisitResult> createVisit({required String appointmentId, String? doctorId}) async {
    _assertNonEmpty('appointmentId', appointmentId);

    final params = <String, dynamic>{
      'p_appointment_id': appointmentId.trim(),
      if (doctorId != null && doctorId.trim().isNotEmpty) 'p_doctor_id': doctorId.trim(),
    };

    final result = await invokeRpc('create_visit', params);
    final created = CreateVisitResult.fromRpcData(result.data);
    if (created == null) {
      throw StateError('Create visit returned an unexpected shape.');
    }
    return created;
  }

  Future<VisitByAppointmentResult> getVisitByAppointment({required String appointmentId}) async {
    _assertNonEmpty('appointmentId', appointmentId);

    final result = await invokeRpc('get_visit_by_appointment', {'p_appointment_id': appointmentId.trim()});
    return VisitByAppointmentResult.fromRpcData(result.data);
  }

  Future<VisitDetail> getVisit({required String visitId}) async {
    _assertNonEmpty('visitId', visitId);

    final result = await invokeRpc('get_visit', {'p_visit_id': visitId.trim()});
    final detail = VisitDetail.fromRow(result.data ?? const {});
    if (detail == null) {
      throw StateError('Get visit returned an unexpected shape.');
    }
    return detail;
  }

  Future<SoapSaveResult> saveSoapNote({
    required String visitId,
    required DateTime expectedUpdatedAt,
    String? subjective,
    String? objective,
    String? assessment,
    String? plan,
    Map<String, dynamic>? specialtyFormJson,
  }) async {
    _assertNonEmpty('visitId', visitId);

    final result = await invokeRpc('save_soap_note', {
      'p_visit_id': visitId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_subjective': ?subjective,
      'p_objective': ?objective,
      'p_assessment': ?assessment,
      'p_plan': ?plan,
      'p_specialty_form_json': ?specialtyFormJson,
    });

    final saved = SoapSaveResult.fromRpcData(result.data);
    if (saved == null) {
      throw StateError('Save SOAP note returned an unexpected shape.');
    }
    return saved;
  }

  Future<CompleteVisitResult> completeVisit({required String visitId, DateTime? expectedUpdatedAt}) async {
    _assertNonEmpty('visitId', visitId);

    final result = await invokeRpc('complete_visit', {
      'p_visit_id': visitId.trim(),
      if (expectedUpdatedAt != null) 'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
    });

    final completed = CompleteVisitResult.fromRpcData(result.data);
    if (completed == null) {
      throw StateError('Complete visit returned an unexpected shape.');
    }
    return completed;
  }

  Future<String> createTreatmentPlan({
    required String visitId,
    required String medicationName,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  }) async {
    _assertNonEmpty('visitId', visitId);
    _assertNonEmpty('medicationName', medicationName);

    final result = await invokeRpc('create_treatment_plan', {
      'p_visit_id': visitId.trim(),
      'p_medication_name': medicationName.trim(),
      'p_dosage': ?dosage,
      'p_frequency': ?frequency,
      'p_duration': ?duration,
      'p_notes': ?notes,
    });

    final id = result.data?['treatment_plan_id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Create treatment plan returned an unexpected shape.');
    }
    return id;
  }

  Future<void> updateTreatmentPlan({
    required String treatmentPlanId,
    String? medicationName,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  }) async {
    _assertNonEmpty('treatmentPlanId', treatmentPlanId);

    await invokeRpc('update_treatment_plan', {
      'p_treatment_plan_id': treatmentPlanId.trim(),
      'p_medication_name': ?medicationName,
      'p_dosage': ?dosage,
      'p_frequency': ?frequency,
      'p_duration': ?duration,
      'p_notes': ?notes,
    });
  }

  Future<void> archiveTreatmentPlan({required String treatmentPlanId}) async {
    _assertNonEmpty('treatmentPlanId', treatmentPlanId);
    await invokeRpc('archive_treatment_plan', {'p_treatment_plan_id': treatmentPlanId.trim()});
  }

  Future<String> registerVisitAttachment({
    required String visitId,
    required String filePath,
    required String fileType,
    required int sizeBytes,
    String? label,
  }) async {
    _assertNonEmpty('visitId', visitId);
    _assertNonEmpty('filePath', filePath);
    _assertNonEmpty('fileType', fileType);

    final result = await invokeRpc('register_visit_attachment', {
      'p_visit_id': visitId.trim(),
      'p_file_path': filePath.trim(),
      'p_file_type': fileType.trim(),
      'p_size_bytes': sizeBytes,
      if (label != null && label.trim().isNotEmpty) 'p_label': label.trim(),
    });

    final id = result.data?['attachment_id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Register visit attachment returned an unexpected shape.');
    }
    return id;
  }

  Future<VisitAttachmentDownloadResult> getVisitAttachmentDownload({required String attachmentId}) async {
    _assertNonEmpty('attachmentId', attachmentId);

    final result = await invokeRpc('get_visit_attachment_download', {'p_attachment_id': attachmentId.trim()});

    final download = VisitAttachmentDownloadResult.fromRpcData(result.data);
    if (download == null) {
      throw StateError('Get visit attachment download returned an unexpected shape.');
    }
    return download;
  }

  Future<PatientVisitsPage> listPatientVisits({required String patientId, int limit = 50, int offset = 0}) async {
    _assertNonEmpty('patientId', patientId);

    final result = await invokeRpc('list_patient_visits', {
      'p_patient_id': patientId.trim(),
      'p_limit': limit,
      'p_offset': offset,
    });

    final page = PatientVisitsPage.fromRpcData(result.data);
    if (page == null) {
      throw StateError('List patient visits returned an unexpected shape.');
    }
    return page;
  }

  Future<List<PatientVisitAttachmentRow>> listPatientVisitAttachments({
    required String patientId,
    int limit = 100,
    int offset = 0,
  }) async {
    _assertNonEmpty('patientId', patientId);

    final result = await invokeRpc('list_patient_visit_attachments', {
      'p_patient_id': patientId.trim(),
      'p_limit': limit,
      'p_offset': offset,
    });

    final rawItems = result.data?['items'];
    if (rawItems is! List) {
      return const [];
    }

    return [
      for (final item in rawItems)
        if (item is Map<String, dynamic>)
          PatientVisitAttachmentRow.fromRow(item)
        else if (item is Map)
          PatientVisitAttachmentRow.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<PatientVisitAttachmentRow>().toList(growable: false);
  }

  Future<Map<String, dynamic>> getSpecialtyFormSchema() async {
    final result = await invokeRpc('get_specialty_form_schema', null);
    return _parseSchemaJson(result.data?['schema_json']);
  }

  Future<Map<String, dynamic>> setSpecialtyFormSchema({required Map<String, dynamic> schemaJson}) async {
    final result = await invokeRpc('set_specialty_form_schema', {'p_schema_json': schemaJson});
    return _parseSchemaJson(result.data?['schema_json']);
  }

  Map<String, dynamic> _parseSchemaJson(Object? schema) {
    if (schema is Map<String, dynamic>) {
      return schema;
    }
    if (schema is Map) {
      return Map<String, dynamic>.from(schema);
    }
    return const {};
  }

  void _assertNonEmpty(String field, String value) {
    if (value.trim().isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
  }
}

final visitRepositoryProvider = Provider<VisitRepository>((ref) {
  return VisitRepository(ref.watch(supabaseClientProvider));
});

/// Result of `create_visit`.
class CreateVisitResult {
  const CreateVisitResult({
    required this.visitId,
    required this.appointmentId,
    required this.status,
    required this.visitDate,
  });

  final String visitId;
  final String appointmentId;
  final String status;
  final DateTime visitDate;

  static CreateVisitResult? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final visitId = data['visit_id']?.toString();
    final appointmentId = data['appointment_id']?.toString();
    final status = data['status']?.toString();
    final visitDateRaw = data['visit_date']?.toString();
    if (visitId == null ||
        visitId.isEmpty ||
        appointmentId == null ||
        appointmentId.isEmpty ||
        status == null ||
        visitDateRaw == null) {
      return null;
    }
    final visitDate = DateTime.tryParse(visitDateRaw);
    if (visitDate == null) {
      return null;
    }
    return CreateVisitResult(visitId: visitId, appointmentId: appointmentId, status: status, visitDate: visitDate);
  }
}

/// Result of `get_visit_by_appointment`.
class VisitByAppointmentResult {
  const VisitByAppointmentResult({this.visitId, this.status});

  final String? visitId;
  final String? status;

  static VisitByAppointmentResult fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return const VisitByAppointmentResult();
    }
    final visitId = data['visit_id'];
    return VisitByAppointmentResult(visitId: visitId?.toString(), status: data['status']?.toString());
  }
}

/// Result of `save_soap_note`.
class SoapSaveResult {
  const SoapSaveResult({required this.visitId, required this.updatedAt});

  final String visitId;
  final DateTime updatedAt;

  static SoapSaveResult? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final visitId = data['visit_id']?.toString();
    final updatedAtRaw = data['updated_at']?.toString();
    if (visitId == null || visitId.isEmpty || updatedAtRaw == null) {
      return null;
    }
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (updatedAt == null) {
      return null;
    }
    return SoapSaveResult(visitId: visitId, updatedAt: updatedAt);
  }
}

/// Result of `complete_visit`.
class CompleteVisitResult {
  const CompleteVisitResult({
    required this.visitId,
    required this.visitStatus,
    required this.appointmentId,
    required this.appointmentStatus,
  });

  final String visitId;
  final String visitStatus;
  final String appointmentId;
  final String appointmentStatus;

  static CompleteVisitResult? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final visitId = data['visit_id']?.toString();
    final visitStatus = data['visit_status']?.toString();
    final appointmentId = data['appointment_id']?.toString();
    final appointmentStatus = data['appointment_status']?.toString();
    if (visitId == null || visitStatus == null || appointmentId == null || appointmentStatus == null) {
      return null;
    }
    return CompleteVisitResult(
      visitId: visitId,
      visitStatus: visitStatus,
      appointmentId: appointmentId,
      appointmentStatus: appointmentStatus,
    );
  }
}

/// Result of `get_visit_attachment_download`.
class VisitAttachmentDownloadResult {
  const VisitAttachmentDownloadResult({
    required this.signedUrl,
    required this.fileType,
    required this.filename,
    required this.expiresAt,
    this.filePath,
  });

  final String signedUrl;
  final String fileType;
  final String filename;
  final DateTime? expiresAt;

  /// Storage object key under `visit-attachments` (preferred download path).
  final String? filePath;

  static VisitAttachmentDownloadResult? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final signedUrl = data['signed_url']?.toString();
    final fileType = data['file_type']?.toString();
    final filename = data['filename']?.toString();
    if (signedUrl == null || fileType == null || filename == null) {
      return null;
    }
    final expiresAtRaw = data['expires_at']?.toString();
    final filePath = data['file_path']?.toString();
    return VisitAttachmentDownloadResult(
      signedUrl: signedUrl,
      fileType: fileType,
      filename: filename,
      expiresAt: expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw),
      filePath: filePath != null && filePath.isNotEmpty ? filePath : null,
    );
  }
}

/// Visit attachment row from `list_patient_visit_attachments`.
class PatientVisitAttachmentRow {
  const PatientVisitAttachmentRow({required this.visitId, required this.visitDate, required this.attachment});

  final String visitId;
  final DateTime visitDate;
  final VisitAttachmentItem attachment;

  static PatientVisitAttachmentRow? fromRow(Map<String, dynamic> row) {
    final visitId = row['visit_id']?.toString();
    final visitDate = parseVisitDate(row['visit_date']);
    final attachment = VisitAttachmentItem.fromRow(row);
    if (visitId == null || visitId.isEmpty || visitDate == null || attachment == null) {
      return null;
    }
    return PatientVisitAttachmentRow(visitId: visitId, visitDate: visitDate, attachment: attachment);
  }
}

/// Paginated patient visit history (`list_patient_visits`).
class PatientVisitsPage {
  const PatientVisitsPage({required this.items, required this.totalCount, required this.limit, required this.offset});

  final List<VisitListItem> items;
  final int totalCount;
  final int limit;
  final int offset;

  static PatientVisitsPage? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final rawItems = data['items'];
    final items = <VisitListItem>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          final parsed = VisitListItem.fromRow(item);
          if (parsed != null) {
            items.add(parsed);
          }
        } else if (item is Map) {
          final parsed = VisitListItem.fromRow(Map<String, dynamic>.from(item));
          if (parsed != null) {
            items.add(parsed);
          }
        }
      }
    }
    return PatientVisitsPage(
      items: items,
      totalCount: _parseInt(data['total_count']) ?? items.length,
      limit: _parseInt(data['limit']) ?? 50,
      offset: _parseInt(data['offset']) ?? 0,
    );
  }

  static int? _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
