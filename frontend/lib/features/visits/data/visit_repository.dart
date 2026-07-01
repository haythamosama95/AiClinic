import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
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
  String get migrationHint => '20260701120000_visit_encounter_workspace.sql';

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
      throw StateError(
        'Get visit returned an unexpected shape. '
        'Ensure migration $migrationHint is applied and the visit record is valid.',
      );
    }
    return detail;
  }

  Future<DocumentationSaveResult> saveVisitDocumentation({
    required String visitId,
    required DateTime expectedUpdatedAt,
    String? complaint,
    String? history,
    String? examination,
    String? diagnosis,
    String? plan,
  }) async {
    _assertNonEmpty('visitId', visitId);

    final result = await invokeRpc('save_visit_documentation', {
      'p_visit_id': visitId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_complaint': ?complaint,
      'p_history': ?history,
      'p_examination': ?examination,
      'p_diagnosis': ?diagnosis,
      'p_plan': ?plan,
    });

    final saved = DocumentationSaveResult.fromRpcData(result.data);
    if (saved == null) {
      throw StateError('Save visit documentation returned an unexpected shape.');
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

  Future<List<CatalogItem>> searchMedications({String? query, int limit = 20}) async {
    final result = await invokeRpc('search_medications', {'p_query': query?.trim() ?? '', 'p_limit': limit});
    return _parseCatalogItems(result.data?['items']);
  }

  Future<CatalogCreateResult> createCatalogMedication({required String name}) async {
    _assertNonEmpty('name', name);

    final result = await invokeRpc('create_catalog_medication', {'p_name': name.trim()});
    final created = CatalogCreateResult.fromRpcData(result.data);
    if (created == null) {
      throw StateError('Create catalog medication returned an unexpected shape.');
    }
    return created;
  }

  /// Bulk-import medication catalog names (bootstrap admin, dev environments only).
  Future<DevCatalogSeedResult> devSeedMedicationsCatalog({required List<String> names}) async {
    return _devSeedCatalog(rpcName: 'dev_seed_medications_catalog', names: names, label: 'medications');
  }

  /// Bulk-import investigation catalog names (bootstrap admin, dev environments only).
  Future<DevCatalogSeedResult> devSeedInvestigationsCatalog({required List<String> names}) async {
    return _devSeedCatalog(rpcName: 'dev_seed_investigations_catalog', names: names, label: 'investigations');
  }

  Future<DevCatalogSeedResult> _devSeedCatalog({
    required String rpcName,
    required List<String> names,
    required String label,
  }) async {
    if (names.isEmpty) {
      return const DevCatalogSeedResult(inserted: 0, requested: 0);
    }

    final result = await invokeRpc(rpcName, {'p_names': names});
    final inserted = result.data?['inserted'];
    final requested = result.data?['requested'];
    if (inserted is! num || requested is! num) {
      throw StateError('Dev seed $label catalog returned an unexpected shape.');
    }

    return DevCatalogSeedResult(inserted: inserted.toInt(), requested: requested.toInt());
  }

  Future<String> createTreatmentPlan({
    required String visitId,
    required String medicationName,
    required String dosage,
    required String frequency,
    required String duration,
    String? medicationId,
    String? notes,
  }) async {
    _assertNonEmpty('visitId', visitId);
    _assertNonEmpty('medicationName', medicationName);
    _assertNonEmpty('dosage', dosage);
    _assertNonEmpty('frequency', frequency);
    _assertNonEmpty('duration', duration);

    final result = await invokeRpc('create_treatment_plan', {
      'p_visit_id': visitId.trim(),
      'p_medication_name': medicationName.trim(),
      'p_dosage': dosage.trim(),
      'p_frequency': frequency.trim(),
      'p_duration': duration.trim(),
      'p_notes': ?notes,
      if (medicationId != null && medicationId.trim().isNotEmpty) 'p_medication_id': medicationId.trim(),
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
    String? medicationId,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  }) async {
    _assertNonEmpty('treatmentPlanId', treatmentPlanId);

    await invokeRpc('update_treatment_plan', {
      'p_treatment_plan_id': treatmentPlanId.trim(),
      'p_medication_name': ?medicationName,
      if (medicationId != null) 'p_medication_id': medicationId.trim().isEmpty ? null : medicationId.trim(),
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

  Future<List<CatalogItem>> listPredefinedVitalSigns() async {
    final result = await invokeRpc('list_predefined_vital_signs', const {});
    return _parseCatalogItems(result.data?['items']);
  }

  Future<String> createVisitVitalSign({
    required String visitId,
    required String name,
    required String value,
    String? unit,
    String? predefinedVitalSignId,
  }) async {
    _assertNonEmpty('visitId', visitId);
    _assertNonEmpty('name', name);
    _assertNonEmpty('value', value);

    final result = await invokeRpc('create_visit_vital_sign', {
      'p_visit_id': visitId.trim(),
      'p_name': name.trim(),
      'p_value': value.trim(),
      'p_unit': ?unit,
      if (predefinedVitalSignId != null && predefinedVitalSignId.trim().isNotEmpty)
        'p_predefined_vital_sign_id': predefinedVitalSignId.trim(),
    });

    final id = result.data?['vital_sign_id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Create visit vital sign returned an unexpected shape.');
    }
    return id;
  }

  Future<void> updateVisitVitalSign({
    required String vitalSignId,
    String? name,
    String? value,
    String? unit,
    String? predefinedVitalSignId,
  }) async {
    _assertNonEmpty('vitalSignId', vitalSignId);

    await invokeRpc('update_visit_vital_sign', {
      'p_vital_sign_id': vitalSignId.trim(),
      'p_name': ?name,
      'p_value': ?value,
      'p_unit': ?unit,
      'p_predefined_vital_sign_id': ?predefinedVitalSignId,
    });
  }

  Future<void> archiveVisitVitalSign({required String vitalSignId}) async {
    _assertNonEmpty('vitalSignId', vitalSignId);
    await invokeRpc('archive_visit_vital_sign', {'p_vital_sign_id': vitalSignId.trim()});
  }

  Future<CatalogCreateResult> createPredefinedVitalSign({required String name, String? defaultUnit}) async {
    _assertNonEmpty('name', name);

    final result = await invokeRpc('create_predefined_vital_sign', {
      'p_name': name.trim(),
      'p_default_unit': ?defaultUnit,
    });

    final created = CatalogCreateResult.fromRpcData(result.data);
    if (created == null) {
      throw StateError('Create predefined vital sign returned an unexpected shape.');
    }
    return created;
  }

  Future<List<CatalogItem>> searchInvestigations({String? query, int limit = 20}) async {
    final result = await invokeRpc('search_investigations', {'p_query': query?.trim() ?? '', 'p_limit': limit});
    return _parseCatalogItems(result.data?['items']);
  }

  Future<CatalogCreateResult> createCatalogInvestigation({required String name}) async {
    _assertNonEmpty('name', name);

    final result = await invokeRpc('create_catalog_investigation', {'p_name': name.trim()});
    final created = CatalogCreateResult.fromRpcData(result.data);
    if (created == null) {
      throw StateError('Create catalog investigation returned an unexpected shape.');
    }
    return created;
  }

  Future<String> createVisitInvestigation({
    required String visitId,
    required String name,
    String? note,
    String? investigationId,
  }) async {
    _assertNonEmpty('visitId', visitId);
    _assertNonEmpty('name', name);

    final result = await invokeRpc('create_visit_investigation', {
      'p_visit_id': visitId.trim(),
      'p_name': name.trim(),
      'p_note': ?note,
      if (investigationId != null && investigationId.trim().isNotEmpty) 'p_investigation_id': investigationId.trim(),
    });

    final id = result.data?['investigation_line_id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Create visit investigation returned an unexpected shape.');
    }
    return id;
  }

  Future<void> updateVisitInvestigation({
    required String investigationLineId,
    String? name,
    String? note,
    String? investigationId,
  }) async {
    _assertNonEmpty('investigationLineId', investigationLineId);

    await invokeRpc('update_visit_investigation', {
      'p_investigation_line_id': investigationLineId.trim(),
      'p_name': ?name,
      'p_note': ?note,
      if (investigationId != null) 'p_investigation_id': investigationId.trim().isEmpty ? null : investigationId.trim(),
    });
  }

  Future<void> archiveVisitInvestigation({required String investigationLineId}) async {
    _assertNonEmpty('investigationLineId', investigationLineId);
    await invokeRpc('archive_visit_investigation', {'p_investigation_line_id': investigationLineId.trim()});
  }

  Future<DateTime?> recordInvestigationResult({required String investigationLineId, String? result}) async {
    _assertNonEmpty('investigationLineId', investigationLineId);

    final rpcResult = await invokeRpc('record_investigation_result', {
      'p_investigation_line_id': investigationLineId.trim(),
      'p_result': ?result,
    });

    return parseVisitDateTime(rpcResult.data?['result_recorded_at']);
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

  Future<void> deleteVisitAttachment({required String attachmentId}) async {
    _assertNonEmpty('attachmentId', attachmentId);
    await invokeRpc('delete_visit_attachment', {'p_attachment_id': attachmentId.trim()});
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

  Future<PatientSafetyContext> getPatientSafetyContext({required String patientId}) async {
    _assertNonEmpty('patientId', patientId);

    final result = await invokeRpc('get_patient_safety_context', {'p_patient_id': patientId.trim()});
    return PatientSafetyContext.fromRpcData(result.data);
  }

  Future<String> createPatientAllergy({required String patientId, required String substance, String? reaction}) async {
    _assertNonEmpty('patientId', patientId);
    _assertNonEmpty('substance', substance);

    final result = await invokeRpc('create_patient_allergy', {
      'p_patient_id': patientId.trim(),
      'p_substance': substance.trim(),
      'p_reaction': ?reaction,
    });

    final id = result.data?['id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Create patient allergy returned an unexpected shape.');
    }
    return id;
  }

  Future<void> updatePatientAllergy({required String allergyId, String? substance, String? reaction}) async {
    _assertNonEmpty('allergyId', allergyId);

    await invokeRpc('update_patient_allergy', {
      'p_allergy_id': allergyId.trim(),
      'p_substance': ?substance,
      'p_reaction': ?reaction,
    });
  }

  Future<void> archivePatientAllergy({required String allergyId}) async {
    _assertNonEmpty('allergyId', allergyId);
    await invokeRpc('archive_patient_allergy', {'p_allergy_id': allergyId.trim()});
  }

  Future<String> createPatientMedication({
    required String patientId,
    required String name,
    String? medicationId,
    String? note,
  }) async {
    _assertNonEmpty('patientId', patientId);
    _assertNonEmpty('name', name);

    final result = await invokeRpc('create_patient_medication', {
      'p_patient_id': patientId.trim(),
      'p_name': name.trim(),
      if (medicationId != null && medicationId.trim().isNotEmpty) 'p_medication_id': medicationId.trim(),
      'p_note': ?note,
    });

    final id = result.data?['id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Create patient medication returned an unexpected shape.');
    }
    return id;
  }

  Future<void> updatePatientMedication({
    required String medicationRecordId,
    String? name,
    String? medicationId,
    String? note,
  }) async {
    _assertNonEmpty('medicationRecordId', medicationRecordId);

    await invokeRpc('update_patient_medication', {
      'p_medication_record_id': medicationRecordId.trim(),
      'p_name': ?name,
      if (medicationId != null) 'p_medication_id': medicationId.trim().isEmpty ? null : medicationId.trim(),
      'p_note': ?note,
    });
  }

  Future<void> archivePatientMedication({required String medicationRecordId}) async {
    _assertNonEmpty('medicationRecordId', medicationRecordId);
    await invokeRpc('archive_patient_medication', {'p_medication_record_id': medicationRecordId.trim()});
  }

  Future<String> createPatientChronicCondition({required String patientId, required String name, String? note}) async {
    _assertNonEmpty('patientId', patientId);
    _assertNonEmpty('name', name);

    final result = await invokeRpc('create_patient_chronic_condition', {
      'p_patient_id': patientId.trim(),
      'p_name': name.trim(),
      'p_note': ?note,
    });

    final id = result.data?['id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Create patient chronic condition returned an unexpected shape.');
    }
    return id;
  }

  Future<void> updatePatientChronicCondition({required String conditionId, String? name, String? note}) async {
    _assertNonEmpty('conditionId', conditionId);

    await invokeRpc('update_patient_chronic_condition', {
      'p_condition_id': conditionId.trim(),
      'p_name': ?name,
      'p_note': ?note,
    });
  }

  Future<void> archivePatientChronicCondition({required String conditionId}) async {
    _assertNonEmpty('conditionId', conditionId);
    await invokeRpc('archive_patient_chronic_condition', {'p_condition_id': conditionId.trim()});
  }

  void _assertNonEmpty(String field, String value) {
    if (value.trim().isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
  }

  List<CatalogItem> _parseCatalogItems(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          ?CatalogItem.fromRow(item)
        else if (item is Map)
          ?CatalogItem.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<CatalogItem>().toList(growable: false);
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

/// Result of `save_visit_documentation`.
class DocumentationSaveResult {
  const DocumentationSaveResult({required this.visitId, required this.updatedAt});

  final String visitId;
  final DateTime updatedAt;

  static DocumentationSaveResult? fromRpcData(Map<String, dynamic>? data) {
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
    return DocumentationSaveResult(visitId: visitId, updatedAt: updatedAt);
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
