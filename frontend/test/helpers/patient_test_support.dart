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

const testBranchAId = '00000000-0000-4000-8000-000000000001';
const testBranchBId = '00000000-0000-4000-8000-000000000002';

/// Builds [count] patients with deterministic names for pagination tests.
List<PatientListItem> samplePatientList({
  int count = 1,
  String branchId = testBranchAId,
  String branchName = 'Branch A',
  String namePrefix = 'Patient',
}) {
  return List.generate(count, (index) {
    final n = index + 1;
    return PatientListItem(
      id: '11111111-1111-4111-8111-${n.toString().padLeft(12, '0')}',
      fullName: '$namePrefix ${n.toString().padLeft(3, '0')}',
      phone: '2012345${n.toString().padLeft(5, '0')}',
      dateOfBirth: DateTime.utc(1990, 1, 15),
      registeringBranchId: branchId,
      registeringBranchName: branchName,
    );
  });
}

/// Standard test patient list item for consistent test data.
PatientListItem samplePatientListItem({
  String id = '11111111-1111-4111-8111-111111111111',
  String fullName = 'Test Patient',
  String? phone = '+1234567890',
  DateTime? dateOfBirth,
  String branchId = testBranchAId,
  String branchName = 'Branch A',
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
  String branchId = testBranchAId,
  String branchName = 'Branch A',
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
    List<PatientListItem> patients = const [],
    this.detail,
    this.duplicates = const [],
    this.createResult = '33333333-3333-4333-8333-333333333333',
    this.searchDelay = Duration.zero,
    this.createDelay = Duration.zero,
    this.archiveDelay = Duration.zero,
    this.searchException,
    this.createException,
    this.updateException,
    this.archiveException,
  }) : patients = List.from(patients);

  final List<PatientListItem> patients;
  final PatientDetail? detail;
  final List<DuplicateCandidate> duplicates;
  final String createResult;
  final Duration searchDelay;
  final Duration createDelay;
  final Duration archiveDelay;
  final Object? searchException;
  final Object? createException;
  final Object? updateException;
  final Object? archiveException;

  CreatePatientInput? lastCreateInput;
  UpdatePatientInput? lastUpdateInput;
  String? lastArchivedId;
  int searchCallCount = 0;
  int createCallCount = 0;
  int getPatientCallCount = 0;
  int archiveCallCount = 0;
  String? lastQuery;
  PatientListScope? lastScope;
  String? lastBranchId;
  int? lastLimit;
  int? lastOffset;
  PatientLastVisitFilter? lastLastVisitFilter;
  PatientSortField? lastSortField;
  final List<int> searchOffsets = [];

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
    lastQuery = query;
    lastScope = scope;
    lastBranchId = branchId;
    lastLimit = limit;
    lastOffset = offset;
    lastLastVisitFilter = lastVisitFilter;
    lastSortField = sortField;
    searchOffsets.add(offset);

    if (searchDelay > Duration.zero) {
      await Future<void>.delayed(searchDelay);
    }
    if (searchException != null) {
      throw searchException!;
    }

    var filtered = patients.toList();
    if (query != null && query.isNotEmpty) {
      final trimmed = query.trim();
      if (RegExp(r'^\d+$').hasMatch(trimmed)) {
        filtered = filtered.where((p) => (p.phone ?? '').replaceAll(RegExp(r'\D'), '').startsWith(trimmed)).toList();
      } else {
        final q = trimmed.toLowerCase();
        filtered = filtered.where((p) => p.fullName.toLowerCase().contains(q)).toList();
      }
    }
    if (scope == PatientListScope.thisBranch && branchId != null) {
      filtered = filtered.where((p) => p.registeringBranchId == branchId).toList();
    }
    filtered = _applyLastVisitFilter(filtered, lastVisitFilter);
    filtered = _applySort(filtered, sortField);
    final page = filtered.skip(offset).take(limit).toList();
    return PatientSearchPage(items: page, totalCount: filtered.length, limit: limit, offset: offset);
  }

  static List<PatientListItem> _applyLastVisitFilter(List<PatientListItem> items, PatientLastVisitFilter filter) {
    final now = DateTime.now().toUtc();
    return switch (filter) {
      PatientLastVisitFilter.any => items,
      PatientLastVisitFilter.never => items.where((p) => p.lastVisitAt == null).toList(),
      PatientLastVisitFilter.last30Days => items.where((p) {
        final visit = p.lastVisitAt;
        return visit != null && now.difference(visit).inDays <= 30;
      }).toList(),
      PatientLastVisitFilter.last90Days => items.where((p) {
        final visit = p.lastVisitAt;
        return visit != null && now.difference(visit).inDays <= 90;
      }).toList(),
      PatientLastVisitFilter.over90Days => items.where((p) {
        final visit = p.lastVisitAt;
        return visit != null && now.difference(visit).inDays > 90;
      }).toList(),
    };
  }

  static List<PatientListItem> _applySort(List<PatientListItem> items, PatientSortField sortField) {
    final sorted = items.toList();
    switch (sortField) {
      case PatientSortField.nameAsc:
        sorted.sort((a, b) => a.fullName.compareTo(b.fullName));
      case PatientSortField.nameDesc:
        sorted.sort((a, b) => b.fullName.compareTo(a.fullName));
      case PatientSortField.lastVisitAsc:
        sorted.sort((a, b) => _compareLastVisitAsc(a.lastVisitAt, b.lastVisitAt));
      case PatientSortField.lastVisitDesc:
        sorted.sort((a, b) => _compareLastVisitAsc(b.lastVisitAt, a.lastVisitAt));
    }
    return sorted;
  }

  static int _compareLastVisitAsc(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }

  @override
  Future<PatientDetail> getPatient(String patientId) async {
    getPatientCallCount++;
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
    createCallCount++;
    lastCreateInput = input;
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    if (createException != null) {
      throw createException!;
    }
    return createResult;
  }

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) async {
    if (updateException != null) {
      throw updateException!;
    }
    lastUpdateInput = input;
    return DateTime.now().toUtc();
  }

  @override
  Future<void> archivePatient(String patientId) async {
    archiveCallCount++;
    if (archiveException != null) {
      throw archiveException!;
    }
    if (archiveDelay > Duration.zero) {
      await Future<void>.delayed(archiveDelay);
    }
    lastArchivedId = patientId;
    if (patients.isNotEmpty) {
      patients.removeWhere((patient) => patient.id == patientId);
    }
  }
}
