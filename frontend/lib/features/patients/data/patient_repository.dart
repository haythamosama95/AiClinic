import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';

/// Patient list/detail mutations via secured RPCs (V1-3).
class PatientRepositoryImpl with AppRpcInvoker implements PatientRepository {
  PatientRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260523140000_patient_management.sql';

  @override
  String get rpcLogDomain => 'patients';

  @override
  Future<PatientSearchPage> searchPatients({
    String? query,
    required PatientListScope scope,
    String? branchId,
    int limit = 25,
    int offset = 0,
  }) async {
    if (scope == PatientListScope.thisBranch && (branchId == null || branchId.trim().isEmpty)) {
      throw ArgumentError('branchId is required when scope is thisBranch');
    }

    final params = <String, dynamic>{
      'p_scope': scope.rpcScopeValue,
      'p_limit': limit,
      'p_offset': offset,
      if (query != null && query.trim().isNotEmpty) 'p_query': query.trim(),
      if (branchId != null && branchId.trim().isNotEmpty) 'p_branch_id': branchId,
    };

    final result = await invokeRpc('search_patients', params);
    return PatientSearchPage.fromRpcData(result.data);
  }

  @override
  Future<PatientDetail> getPatient(String patientId) async {
    final id = patientId.trim();
    if (id.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Patient id is required.'),
      );
    }

    final result = await invokeRpc('get_patient', {'p_patient_id': id});
    final detail = PatientDetail.fromRow(result.data ?? {});
    if (detail == null) {
      throw StateError('Patient profile was returned in an unexpected shape.');
    }
    return detail;
  }

  @override
  Future<List<DuplicateCandidate>> checkDuplicates({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? excludePatientId,
  }) async {
    final result = await invokeRpc('check_patient_duplicates', {
      if (fullName != null) 'p_full_name': fullName.trim(),
      if (phone != null) 'p_phone': phone.trim(),
      if (dateOfBirth != null) 'p_date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'p_exclude_patient_id': ?excludePatientId,
    });

    return parseDuplicateCandidates(result.data?['candidates']);
  }

  @override
  Future<String> createPatient(CreatePatientInput input) async {
    final name = input.fullName.trim();
    if (name.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Full name is required.'),
      );
    }

    final phone = input.phone.trim();
    if (phone.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Mobile number is required.'),
      );
    }

    final result = await invokeRpc('create_patient', {
      'p_active_branch_id': input.activeBranchId,
      'p_full_name': name,
      'p_phone': phone,
      'p_acknowledge_duplicate': input.acknowledgeDuplicate,
      if (input.dateOfBirth != null) 'p_date_of_birth': input.dateOfBirth!.toIso8601String().split('T').first,
      if (input.gender != null) 'p_gender': input.gender!.wireValue,
      if (input.maritalStatus != null) 'p_marital_status': input.maritalStatus!.wireValue,
      if (input.notes != null) 'p_notes': input.notes!.trim(),
    });

    final patientId = result.data?['patient_id']?.toString();
    if (patientId == null || patientId.isEmpty) {
      throw StateError('Patient was created but no patient_id was returned.');
    }
    return patientId;
  }

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) async {
    final name = input.fullName.trim();
    if (name.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Full name is required.'),
      );
    }

    final result = await invokeRpc('update_patient', {
      'p_patient_id': input.patientId,
      'p_full_name': name,
      'p_expected_updated_at': input.expectedUpdatedAt.toUtc().toIso8601String(),
      'p_acknowledge_duplicate': input.acknowledgeDuplicate,
      if (input.phone != null) 'p_phone': input.phone!.trim(),
      if (input.dateOfBirth != null) 'p_date_of_birth': input.dateOfBirth!.toIso8601String().split('T').first,
      if (input.gender != null) 'p_gender': input.gender!.wireValue,
      if (input.maritalStatus != null) 'p_marital_status': input.maritalStatus!.wireValue,
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
    return parsed.toUtc();
  }

  @override
  Future<void> archivePatient(String patientId) async {
    await invokeRpc('archive_patient', {'p_patient_id': patientId});
  }

  /// Parses `candidates` from RPC success or `DUPLICATE_WARNING` error payloads.
  static List<DuplicateCandidate> parseDuplicateCandidates(Object? raw) {
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
  return PatientRepositoryImpl(ref.watch(supabaseClientProvider));
});
