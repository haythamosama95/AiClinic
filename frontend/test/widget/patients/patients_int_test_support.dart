import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';

import '../../helpers/patient_test_support.dart';

/// Fake repository that keeps list and detail in sync across create/update.
class StatefulFakePatientRepository extends FakePatientRepository {
  StatefulFakePatientRepository({
    super.patients,
    PatientDetail? detail,
    super.createResult,
    super.createException,
    super.updateException,
    super.searchException,
    super.archiveException,
  }) : _detail = detail;

  PatientDetail? _detail;

  @override
  PatientDetail? get detail => _detail;

  @override
  Future<PatientDetail> getPatient(String patientId) async {
    getPatientCallCount++;
    if (_detail != null && _detail!.id == patientId) {
      return _detail!;
    }
    throw StateError('Patient not found: $patientId');
  }

  @override
  Future<String> createPatient(CreatePatientInput input) async {
    final id = await super.createPatient(input);
    final item = PatientListItem(
      id: id,
      fullName: input.fullName,
      phone: input.phone,
      dateOfBirth: input.dateOfBirth,
      gender: input.gender,
      registeringBranchId: input.activeBranchId,
      registeringBranchName: 'Branch A',
    );
    patients.add(item);
    _detail = PatientDetail(
      id: id,
      fullName: input.fullName,
      phone: input.phone,
      dateOfBirth: input.dateOfBirth,
      gender: input.gender,
      maritalStatus: input.maritalStatus,
      notes: input.notes,
      branchId: input.activeBranchId,
      branchName: 'Branch A',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    return id;
  }

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) async {
    final updatedAt = await super.updatePatient(input);
    if (_detail != null && _detail!.id == input.patientId) {
      _detail = _detail!.copyWith(
        fullName: input.fullName,
        phone: input.phone,
        dateOfBirth: input.dateOfBirth,
        gender: input.gender,
        maritalStatus: input.maritalStatus,
        notes: input.notes,
        updatedAt: updatedAt,
      );
    }
    final index = patients.indexWhere((p) => p.id == input.patientId);
    if (index >= 0) {
      patients[index] = patients[index].copyWith(
        fullName: input.fullName,
        phone: input.phone,
        dateOfBirth: input.dateOfBirth,
        gender: input.gender,
      );
    }
    return updatedAt;
  }
}

/// Fails the first [failUntil] search calls, then succeeds.
class FlakySearchPatientRepository extends FakePatientRepository {
  FlakySearchPatientRepository({required super.patients, this.failUntil = 1});

  final int failUntil;
  var _searchAttempts = 0;

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
    _searchAttempts++;
    if (_searchAttempts <= failUntil) {
      searchCallCount++;
      throw StateError('Network offline');
    }
    return super.searchPatients(
      query: query,
      scope: scope,
      branchId: branchId,
      limit: limit,
      offset: offset,
      lastVisitFilter: lastVisitFilter,
      sortField: sortField,
    );
  }
}
