import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_result.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/usecases/archive_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/check_duplicates.dart';
import 'package:ai_clinic/features/patients/domain/usecases/create_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/get_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/reassign_patient_mrn.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/patients/domain/usecases/update_patient.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';

void main() {
  late _RecordingPatientRepository repository;

  setUp(() {
    repository = _RecordingPatientRepository();
  });

  group('ArchivePatient', () {
    test('forwards patientId and returns repository result', () async {
      final localRepo = _RecordingPatientRepository();
      const patientId = 'patient-1';

      await ArchivePatient(localRepo).call(patientId);

      expect(localRepo.lastArchivedId, patientId);
    });

    test('propagates repository errors', () {
      repository.archiveException = StateError('archive failed');
      expect(ArchivePatient(repository).call('id'), throwsA(isA<StateError>()));
    });
  });

  group('CheckDuplicates', () {
    test('forwards all arguments unchanged', () async {
      final dob = DateTime.utc(1990, 1, 1);
      const candidates = [DuplicateCandidate(id: 'dup-1', fullName: 'Dup', branchName: 'Main')];
      repository.duplicates = candidates;

      final result = await CheckDuplicates(repository).call(
        fullName: 'Jane Doe',
        phone: '+123',
        dateOfBirth: dob,
        excludePatientId: 'exclude-me',
      );

      expect(repository.lastDuplicateFullName, 'Jane Doe');
      expect(repository.lastDuplicatePhone, '+123');
      expect(repository.lastDuplicateDob, dob);
      expect(repository.lastExcludePatientId, 'exclude-me');
      expect(result, same(candidates));
    });

    test('propagates repository errors', () {
      repository.checkDuplicatesException = Exception('dup check failed');
      expect(
        CheckDuplicates(repository).call(fullName: 'x'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CreatePatient', () {
    test('forwards input and returns repository result', () async {
      const input = CreatePatientInput(
        activeBranchId: testBranchAId,
        fullName: 'New Patient',
        phone: '2017000099',
      );
      const expected = CreatePatientResult(patientId: 'new-id', mrn: 'MRN-000099');
      repository.createResult = expected;

      final result = await CreatePatient(repository).call(input);

      expect(repository.lastCreateInput, same(input));
      expect(result, same(expected));
    });

    test('propagates repository errors', () {
      repository.createException = StateError('create failed');
      expect(
        CreatePatient(repository).call(
          const CreatePatientInput(activeBranchId: testBranchAId, fullName: 'x', phone: '1'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('GetPatient', () {
    test('forwards patientId and returns repository result', () async {
      const patientId = 'detail-id';
      final detail = samplePatientDetail(id: patientId);
      repository.detail = detail;

      final result = await GetPatient(repository).call(patientId);

      expect(repository.lastGetPatientId, patientId);
      expect(result, same(detail));
    });

    test('propagates repository errors', () {
      repository.getPatientException = StateError('not found');
      expect(GetPatient(repository).call('missing'), throwsA(isA<StateError>()));
    });
  });

  group('ReassignPatientMrn', () {
    test('forwards arguments and returns repository result', () async {
      repository.reassignResult = 'MRN-NEW';

      final result = await ReassignPatientMrn(repository).call(
        patientId: 'patient-9',
        newMrn: 'MRN-NEW',
      );

      expect(repository.lastReassignPatientId, 'patient-9');
      expect(repository.lastReassignNewMrn, 'MRN-NEW');
      expect(result, 'MRN-NEW');
    });

    test('propagates repository errors', () {
      repository.reassignException = StateError('reassign failed');
      expect(
        ReassignPatientMrn(repository).call(patientId: 'id', newMrn: 'MRN-1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('SearchPatients', () {
    test('forwards all arguments unchanged', () async {
      const page = PatientSearchPage(items: [], totalCount: 0, limit: 10, offset: 5);
      repository.searchPage = page;

      final result = await SearchPatients(repository).call(
        query: 'ahmed',
        scope: PatientListScope.thisBranch,
        branchId: testBranchBId,
        limit: 10,
        offset: 5,
        lastVisitFilter: PatientLastVisitFilter.last30Days,
        sortField: PatientSortField.nameDesc,
      );

      expect(repository.lastQuery, 'ahmed');
      expect(repository.lastScope, PatientListScope.thisBranch);
      expect(repository.lastBranchId, testBranchBId);
      expect(repository.lastLimit, 10);
      expect(repository.lastOffset, 5);
      expect(repository.lastLastVisitFilter, PatientLastVisitFilter.last30Days);
      expect(repository.lastSortField, PatientSortField.nameDesc);
      expect(result, same(page));
    });

    test('propagates repository errors', () {
      repository.searchException = StateError('search failed');
      expect(
        SearchPatients(repository).call(scope: PatientListScope.allBranches),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('UpdatePatient', () {
    test('forwards input and returns repository result', () async {
      final updatedAt = DateTime.utc(2026, 3, 1);
      final input = UpdatePatientInput(
        patientId: 'patient-1',
        fullName: 'Updated',
        expectedUpdatedAt: DateTime.utc(2026, 1, 1),
      );
      repository.updateResult = updatedAt;

      final result = await UpdatePatient(repository).call(input);

      expect(repository.lastUpdateInput, same(input));
      expect(result, updatedAt);
    });

    test('propagates repository errors', () {
      repository.updateException = StateError('update failed');
      expect(
        UpdatePatient(repository).call(
          UpdatePatientInput(
            patientId: 'id',
            fullName: 'x',
            expectedUpdatedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _RecordingPatientRepository implements PatientRepository {
  PatientSearchPage searchPage = const PatientSearchPage(items: [], totalCount: 0, limit: 25, offset: 0);
  PatientDetail? detail;
  List<DuplicateCandidate> duplicates = const [];
  CreatePatientResult createResult = const CreatePatientResult(patientId: 'created-id', mrn: 'MRN-000001');
  DateTime updateResult = DateTime.utc(2026, 1, 2);
  String reassignResult = 'MRN-REASSIGNED';

  Object? searchException;
  Object? getPatientException;
  Object? checkDuplicatesException;
  Object? createException;
  Object? updateException;
  Object? archiveException;
  Object? reassignException;

  String? lastQuery;
  PatientListScope? lastScope;
  String? lastBranchId;
  int? lastLimit;
  int? lastOffset;
  PatientLastVisitFilter? lastLastVisitFilter;
  PatientSortField? lastSortField;

  String? lastGetPatientId;
  String? lastDuplicateFullName;
  String? lastDuplicatePhone;
  DateTime? lastDuplicateDob;
  String? lastExcludePatientId;
  CreatePatientInput? lastCreateInput;
  UpdatePatientInput? lastUpdateInput;
  String? lastArchivedId;
  String? lastReassignPatientId;
  String? lastReassignNewMrn;

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
    lastQuery = query;
    lastScope = scope;
    lastBranchId = branchId;
    lastLimit = limit;
    lastOffset = offset;
    lastLastVisitFilter = lastVisitFilter;
    lastSortField = sortField;
    if (searchException != null) {
      throw searchException!;
    }
    return searchPage;
  }

  @override
  Future<PatientDetail> getPatient(String patientId) async {
    lastGetPatientId = patientId;
    if (getPatientException != null) {
      throw getPatientException!;
    }
    if (detail != null) {
      return detail!;
    }
    throw StateError('missing detail');
  }

  @override
  Future<List<DuplicateCandidate>> checkDuplicates({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? excludePatientId,
  }) async {
    lastDuplicateFullName = fullName;
    lastDuplicatePhone = phone;
    lastDuplicateDob = dateOfBirth;
    lastExcludePatientId = excludePatientId;
    if (checkDuplicatesException != null) {
      throw checkDuplicatesException!;
    }
    return duplicates;
  }

  @override
  Future<CreatePatientResult> createPatient(CreatePatientInput input) async {
    lastCreateInput = input;
    if (createException != null) {
      throw createException!;
    }
    return createResult;
  }

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) async {
    lastUpdateInput = input;
    if (updateException != null) {
      throw updateException!;
    }
    return updateResult;
  }

  @override
  Future<void> archivePatient(String patientId) async {
    lastArchivedId = patientId;
    if (archiveException != null) {
      throw archiveException!;
    }
  }

  @override
  Future<String> reassignPatientMrn({required String patientId, required String newMrn}) async {
    lastReassignPatientId = patientId;
    lastReassignNewMrn = newMrn;
    if (reassignException != null) {
      throw reassignException!;
    }
    return reassignResult;
  }
}
