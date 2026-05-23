import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';

/// Paginated patient list/search result from `search_patients`.
class PatientSearchPage {
  const PatientSearchPage({required this.items, required this.totalCount, required this.limit, required this.offset});

  final List<PatientListItem> items;
  final int totalCount;
  final int limit;
  final int offset;

  factory PatientSearchPage.fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return const PatientSearchPage(items: [], totalCount: 0, limit: 25, offset: 0);
    }

    final rawItems = data['items'];
    final items = <PatientListItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map) {
          final item = PatientListItem.fromRow(Map<String, dynamic>.from(entry));
          if (item != null) {
            items.add(item);
          }
        }
      }
    }

    return PatientSearchPage(
      items: items,
      totalCount: _readInt(data['total_count'], fallback: items.length),
      limit: _readInt(data['limit'], fallback: 25),
      offset: _readInt(data['offset'], fallback: 0),
    );
  }

  static int _readInt(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

/// Input for [PatientRepository.createPatient].
class CreatePatientInput {
  const CreatePatientInput({
    required this.activeBranchId,
    required this.fullName,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.nationalId,
    this.notes,
    this.acknowledgeDuplicate = false,
  });

  final String activeBranchId;
  final String fullName;
  final String? phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final String? nationalId;
  final String? notes;
  final bool acknowledgeDuplicate;
}

/// Input for [PatientRepository.updatePatient].
class UpdatePatientInput {
  const UpdatePatientInput({
    required this.patientId,
    required this.fullName,
    required this.expectedUpdatedAt,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.nationalId,
    this.notes,
    this.acknowledgeDuplicate = false,
  });

  final String patientId;
  final String fullName;
  final DateTime expectedUpdatedAt;
  final String? phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final String? nationalId;
  final String? notes;
  final bool acknowledgeDuplicate;
}

/// Patient list/detail mutations via secured RPCs (V1-3).
class PatientRepository {
  PatientRepository(this._client);

  final SupabaseClient _client;

  Future<PatientSearchPage> searchPatients({
    String? query,
    required PatientListScope scope,
    String? branchId,
    int limit = 25,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'p_scope': scope.rpcScopeValue,
      'p_limit': limit,
      'p_offset': offset,
      if (query != null && query.trim().isNotEmpty) 'p_query': query.trim(),
      if (scope == PatientListScope.thisBranch && branchId != null) 'p_branch_id': branchId,
    };

    final result = await _invoke('search_patients', params);
    return PatientSearchPage.fromRpcData(result.data);
  }

  Future<PatientDetail> getPatient(String patientId) async {
    final result = await _invoke('get_patient', {'p_patient_id': patientId});
    final detail = PatientDetail.fromRow(result.data ?? {});
    if (detail == null) {
      throw StateError('Patient profile was returned in an unexpected shape.');
    }
    return detail;
  }

  Future<List<DuplicateCandidate>> checkDuplicates({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? nationalId,
    String? excludePatientId,
  }) async {
    final result = await _invoke('check_patient_duplicates', {
      if (fullName != null) 'p_full_name': fullName.trim(),
      if (phone != null) 'p_phone': phone.trim(),
      if (dateOfBirth != null) 'p_date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      if (nationalId != null) 'p_national_id': nationalId.trim(),
      if (excludePatientId != null) 'p_exclude_patient_id': excludePatientId,
    });

    return _parseCandidates(result.data?['candidates']);
  }

  Future<String> createPatient(CreatePatientInput input) async {
    final name = input.fullName.trim();
    if (name.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Full name is required.'),
      );
    }

    final result = await _invoke('create_patient', {
      'p_active_branch_id': input.activeBranchId,
      'p_full_name': name,
      'p_acknowledge_duplicate': input.acknowledgeDuplicate,
      if (input.phone != null) 'p_phone': input.phone!.trim(),
      if (input.dateOfBirth != null) 'p_date_of_birth': input.dateOfBirth!.toIso8601String().split('T').first,
      if (input.gender != null) 'p_gender': input.gender!.wireValue,
      if (input.nationalId != null) 'p_national_id': input.nationalId!.trim(),
      if (input.notes != null) 'p_notes': input.notes!.trim(),
    });

    final patientId = result.data?['patient_id']?.toString();
    if (patientId == null || patientId.isEmpty) {
      throw StateError('Patient was created but no patient_id was returned.');
    }
    return patientId;
  }

  Future<DateTime> updatePatient(UpdatePatientInput input) async {
    final name = input.fullName.trim();
    if (name.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Full name is required.'),
      );
    }

    final result = await _invoke('update_patient', {
      'p_patient_id': input.patientId,
      'p_full_name': name,
      'p_expected_updated_at': input.expectedUpdatedAt.toUtc().toIso8601String(),
      'p_acknowledge_duplicate': input.acknowledgeDuplicate,
      if (input.phone != null) 'p_phone': input.phone!.trim(),
      if (input.dateOfBirth != null) 'p_date_of_birth': input.dateOfBirth!.toIso8601String().split('T').first,
      if (input.gender != null) 'p_gender': input.gender!.wireValue,
      if (input.nationalId != null) 'p_national_id': input.nationalId!.trim(),
      if (input.notes != null) 'p_notes': input.notes!.trim(),
    });

    final updatedAt = result.data?['updated_at']?.toString();
    if (updatedAt == null) {
      throw StateError('Patient was updated but no updated_at was returned.');
    }
    final parsed = DateTime.tryParse(updatedAt);
    if (parsed == null) {
      throw StateError('Patient updated_at could not be parsed: $updatedAt');
    }
    return parsed;
  }

  Future<void> archivePatient(String patientId) async {
    await _invoke('archive_patient', {'p_patient_id': patientId});
  }

  Future<RpcResult> _invoke(String functionName, Map<String, dynamic> params) async {
    AppLog.fine('patients.rpc.invoke fn=$functionName params=${params.keys.join(',')}');

    try {
      final raw = await _client.rpc(functionName, params: params);
      final result = RpcResult.fromDynamic(raw);
      if (!result.success) {
        AppLog.warning(
          'patients.rpc.rejected fn=$functionName code=${result.errorCode} '
          'message=${result.errorMessage}',
        );
        throw RpcFailure(result);
      }
      return result;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.message.contains('Could not find the function')) {
        throw RpcFailure(
          RpcResult(
            success: false,
            errorCode: 'RPC_NOT_APPLIED',
            errorMessage:
                'Database function "$functionName" is missing. Apply backend migrations '
                '(20260523140000_patient_management.sql) and restart Supabase.',
          ),
        );
      }
      rethrow;
    }
  }

  List<DuplicateCandidate> _parseCandidates(Object? raw) {
    if (raw is! List) {
      return const [];
    }

    final candidates = <DuplicateCandidate>[];
    for (final entry in raw) {
      if (entry is Map) {
        final candidate = DuplicateCandidate.fromRow(Map<String, dynamic>.from(entry));
        if (candidate != null) {
          candidates.add(candidate);
        }
      }
    }
    return candidates;
  }
}

final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepository(ref.watch(supabaseClientProvider));
});
