// Test-only helpers; not imported by production code.
// ignore_for_file: depend_on_referenced_packages

import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';

const _testBranchId = '44444444-4444-4444-8444-444444444444';
const _testBranchName = 'Test Branch';

/// Standard test patient list item for consistent test data.
PatientListItem samplePatientListItem({
  String id = '11111111-1111-4111-8111-111111111111',
  String fullName = 'Test Patient',
  String? phone = '+1234567890',
  DateTime? dateOfBirth,
  String branchId = _testBranchId,
  String branchName = _testBranchName,
}) {
  return PatientListItem(
    id: id,
    fullName: fullName,
    phone: phone,
    dateOfBirth: dateOfBirth ?? DateTime.utc(1990, 1, 15),
    registeringBranchId: branchId,
    registeringBranchName: branchName,
  );
}

/// Standard test patient detail for consistent test data.
PatientDetail samplePatientDetail({
  String id = '11111111-1111-4111-8111-111111111111',
  String fullName = 'Test Patient',
  String? phone = '+1234567890',
  DateTime? dateOfBirth,
  PatientGender? gender = PatientGender.male,
  String? notes,
  String branchId = _testBranchId,
  String branchName = _testBranchName,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return PatientDetail(
    id: id,
    fullName: fullName,
    phone: phone,
    dateOfBirth: dateOfBirth ?? DateTime.utc(1990, 1, 15),
    gender: gender,
    notes: notes,
    branchId: branchId,
    branchName: branchName,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 2),
  );
}

/// In-memory patient repository fake for widget and integration tests.
class FakePatientRepository implements PatientRepository {
  FakePatientRepository({
    this.patients = const [],
    this.detail,
    this.duplicates = const [],
    this.createResult = '33333333-3333-4333-8333-333333333333',
  });

  final List<PatientListItem> patients;
  final PatientDetail? detail;
  final List<DuplicateCandidate> duplicates;
  final String createResult;

  CreatePatientInput? lastCreateInput;
  UpdatePatientInput? lastUpdateInput;
  String? lastArchivedId;
  int searchCallCount = 0;

  @override
  Future<PatientSearchPage> searchPatients({
    String? query,
    required PatientListScope scope,
    String? branchId,
    int limit = 25,
    int offset = 0,
    PatientLastVisitFilter lastVisitFilter = PatientLastVisitFilter.any,
    PatientSortField sortField = PatientSortField.nameAsc,
  }) async {
    searchCallCount++;
    var filtered = patients.toList();
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      filtered = filtered.where((p) => p.fullName.toLowerCase().contains(q)).toList();
    }
    if (scope == PatientListScope.thisBranch && branchId != null) {
      filtered = filtered.where((p) => p.registeringBranchId == branchId).toList();
    }
    final page = filtered.skip(offset).take(limit).toList();
    return PatientSearchPage(items: page, totalCount: filtered.length, limit: limit, offset: offset);
  }

  @override
  Future<PatientDetail> getPatient(String patientId) async {
    if (detail != null && detail!.id == patientId) {
      return detail!;
    }
    throw StateError('Patient not found: $patientId');
  }

  @override
  Future<List<DuplicateCandidate>> checkDuplicates({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? excludePatientId,
  }) async {
    return duplicates;
  }

  @override
  Future<String> createPatient(CreatePatientInput input) async {
    lastCreateInput = input;
    return createResult;
  }

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) async {
    lastUpdateInput = input;
    return DateTime.now().toUtc();
  }

  @override
  Future<void> archivePatient(String patientId) async {
    lastArchivedId = patientId;
  }
}
