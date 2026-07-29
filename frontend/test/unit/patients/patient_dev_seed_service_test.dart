import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/patients/data/patient_dev_seed_service.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_result.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_dev_seed_data.dart';
import 'package:ai_clinic/features/patients/domain/patient_dev_seed_spec.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';

const _mainBranchId = testBranchAId;
const _otherBranchId = testBranchBId;
const _createdSecondBranchId = '00000000-0000-4000-8000-000000000099';
const _staffMemberId = '00000000-0000-4000-8000-000000000010';

void main() {
  group('PatientDevSeedOutcome.isSuccess', () {
    test('is true when errorMessage is null', () {
      const outcome = PatientDevSeedOutcome(
        created: 3,
        archived: 1,
        skippedBecauseAlreadySeeded: false,
      );
      expect(outcome.isSuccess, isTrue);
    });

    test('is false when errorMessage is set', () {
      const outcome = PatientDevSeedOutcome(
        created: 0,
        archived: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: 'failed',
      );
      expect(outcome.isSuccess, isFalse);
    });
  });

  group('PatientDevSeedService.seed', () {
    late _SeedPatientRepository patients;
    late _FakeBranchRepository branches;
    late _FakeStaffAdminRepository staffAdmin;

    PatientDevSeedService createService() {
      return PatientDevSeedService(
        patients: patients,
        branches: branches,
        staffAdmin: staffAdmin,
      );
    }

    AuthSessionContext authContext({
      bool setupRequired = false,
      List<String> branchIds = const [_mainBranchId],
      String? activeBranchId = _mainBranchId,
    }) {
      return sampleAuthSessionContext(
        setupRequired: setupRequired,
        branchIds: branchIds,
        activeBranchId: activeBranchId,
      );
    }

    setUp(() {
      patients = _SeedPatientRepository();
      branches = _FakeBranchRepository(
        branches: [
          const BranchListItem(id: _mainBranchId, name: 'Main Branch', isActive: true),
        ],
      );
      staffAdmin = _FakeStaffAdminRepository(
        detail: StaffMemberDetail(
          id: _staffMemberId,
          fullName: 'Test Staff',
          role: StaffRole.administrator,
          isActive: true,
          branchIds: [_mainBranchId],
          primaryBranchId: _mainBranchId,
        ),
      );
    });

    test('returns select-branch error when organization or branch is missing', () async {
      final service = createService();

      final noOrg = await service.seed(
        authContext(setupRequired: true),
        reloadAuthContext: () async {},
      );
      final noBranch = await service.seed(
        authContext(branchIds: const [], activeBranchId: null),
        reloadAuthContext: () async {},
      );

      for (final outcome in [noOrg, noBranch]) {
        expect(outcome.created, 0);
        expect(outcome.archived, 0);
        expect(outcome.skippedBecauseAlreadySeeded, isFalse);
        expect(outcome.errorMessage, 'Select an active branch before seeding patients.');
        expect(outcome.isSuccess, isFalse);
      }
      expect(patients.searchCallCount, 0);
    });

    test('skips when dev patients already exist', () async {
      patients.searchPage = const PatientSearchPage(items: [], totalCount: 2, limit: 1, offset: 0);
      final service = createService();

      final outcome = await service.seed(authContext(), reloadAuthContext: () async {});

      expect(outcome.skippedBecauseAlreadySeeded, isTrue);
      expect(outcome.created, 0);
      expect(outcome.archived, 0);
      expect(outcome.isSuccess, isTrue);
      expect(patients.lastSearchQuery, PatientDevSeedSpec.devNamePrefix.trim());
      expect(patients.lastSearchScope, PatientListScope.allBranches);
      expect(patients.lastSearchLimit, 1);
      expect(branches.listCalls, 0);
    });

    test('creates second branch when no other branch exists', () async {
      final service = createService();

      final outcome = await service.seed(authContext(), reloadAuthContext: () async {});

      expect(outcome.isSuccess, isTrue);
      expect(branches.createCalls, hasLength(1));
      expect(branches.createCalls.single.name, 'Dev Second Branch');
      expect(branches.createCalls.single.code, 'DEV-2ND');
      expect(branches.createCalls.single.address, 'Dev seed address');
      expect(outcome.otherBranchName, 'Dev Second Branch');
    });

    test('reuses first non-main branch without creating a new one', () async {
      branches.branches = [
        const BranchListItem(id: _mainBranchId, name: 'Main Branch', isActive: true),
        const BranchListItem(id: _otherBranchId, name: 'South Clinic', isActive: true),
      ];
      final service = createService();

      final outcome = await service.seed(
        authContext(branchIds: [_mainBranchId, _otherBranchId]),
        reloadAuthContext: () async {},
      );

      expect(outcome.isSuccess, isTrue);
      expect(branches.createCalls, isEmpty);
      expect(outcome.otherBranchName, 'South Clinic');
      expect(
        patients.createdBranchIds.where((branchId) => branchId == _otherBranchId),
        isNotEmpty,
      );
    });

    test('invokes reloadAuthContext when staff branch assignment changes', () async {
      var reloadCount = 0;
      final service = createService();

      final outcome = await service.seed(
        authContext(branchIds: [_mainBranchId]),
        reloadAuthContext: () async {
          reloadCount += 1;
        },
      );

      expect(outcome.isSuccess, isTrue);
      expect(reloadCount, 1);
      expect(staffAdmin.updateCalls, hasLength(1));
      expect(
        staffAdmin.updateCalls.single.branchIds,
        containsAll([_mainBranchId, _createdSecondBranchId]),
      );
    });

    test('does not reload auth when staff already assigned to other branch', () async {
      branches.branches = [
        const BranchListItem(id: _mainBranchId, name: 'Main Branch', isActive: true),
        const BranchListItem(id: _otherBranchId, name: 'South Clinic', isActive: true),
      ];
      staffAdmin.detail = StaffMemberDetail(
        id: _staffMemberId,
        fullName: 'Test Staff',
        role: StaffRole.administrator,
        isActive: true,
        branchIds: [_mainBranchId, _otherBranchId],
        primaryBranchId: _mainBranchId,
      );
      var reloadCount = 0;
      final service = createService();

      await service.seed(
        authContext(branchIds: [_mainBranchId, _otherBranchId]),
        reloadAuthContext: () async {
          reloadCount += 1;
        },
      );

      expect(reloadCount, 0);
      expect(staffAdmin.fetchCalls, 0);
      expect(staffAdmin.updateCalls, isEmpty);
    });

    test('creates all seed patients and archives flagged rows', () async {
      final service = createService();

      final outcome = await service.seed(authContext(), reloadAuthContext: () async {});

      expect(outcome.isSuccess, isTrue);
      expect(outcome.created, PatientDevSeedData.patients.length);
      expect(outcome.archived, PatientDevSeedData.patients.where((spec) => spec.archiveAfterCreate).length);
      expect(patients.createCallCount, PatientDevSeedData.patients.length);
      expect(patients.archiveCallCount, 2);
      expect(
        patients.createdInputs.map((input) => input.mrn).toList(),
        [
          for (var i = 0; i < PatientDevSeedData.patients.length; i++)
            PatientDevSeedSpec.mrnForSeedOrder(i + 1),
        ],
      );
    });

    test('falls back to first branch id when activeBranchId is null', () async {
      final service = createService();

      final outcome = await service.seed(
        authContext(activeBranchId: null, branchIds: [_mainBranchId]),
        reloadAuthContext: () async {},
      );

      expect(outcome.isSuccess, isTrue);
      expect(
        patients.createdBranchIds.where((branchId) => branchId == _mainBranchId),
        isNotEmpty,
      );
    });

    test('returns RpcFailure message when branch listing fails', () async {
      branches.listException = RpcFailure(
        const RpcResult(success: false, errorCode: 'FORBIDDEN', errorMessage: 'Branch list denied'),
      );
      final service = createService();

      final outcome = await service.seed(authContext(), reloadAuthContext: () async {});

      expect(outcome.isSuccess, isFalse);
      expect(outcome.created, 0);
      expect(outcome.archived, 0);
      expect(outcome.errorMessage, 'Branch list denied');
    });

    test('returns prefixed message for generic exceptions', () async {
      branches.listException = Exception('disk full');
      final service = createService();

      final outcome = await service.seed(authContext(), reloadAuthContext: () async {});

      expect(outcome.isSuccess, isFalse);
      expect(outcome.errorMessage, 'Patient seed failed: Exception: disk full');
    });

    test('retries create with acknowledgeDuplicate after DUPLICATE_WARNING', () async {
      patients.duplicateWarningOnCreateIndex = 0;
      final service = createService();

      final outcome = await service.seed(authContext(), reloadAuthContext: () async {});

      expect(outcome.isSuccess, isTrue);
      expect(patients.createCallCount, PatientDevSeedData.patients.length + 1);
      expect(patients.createdInputs.first.acknowledgeDuplicate, isFalse);
      expect(patients.createdInputs[1].acknowledgeDuplicate, isTrue);
    });

    test('surfaces non-duplicate RpcFailure from create', () async {
      patients.createException = RpcFailure(
        const RpcResult(success: false, errorCode: 'STALE_PATIENT', errorMessage: 'Patient was updated elsewhere'),
      );
      final service = createService();

      final outcome = await service.seed(authContext(), reloadAuthContext: () async {});

      expect(outcome.isSuccess, isFalse);
      expect(outcome.errorMessage, 'Patient was updated elsewhere');
      expect(outcome.created, 0);
    });

    test('returns prefixed message when staff detail is missing', () async {
      staffAdmin.detail = null;
      final service = createService();

      final outcome = await service.seed(authContext(), reloadAuthContext: () async {});

      expect(outcome.isSuccess, isFalse);
      expect(
        outcome.errorMessage,
        'Patient seed failed: Bad state: Could not load your staff profile to assign the second branch.',
      );
    });
  });
}

class _SeedPatientRepository implements PatientRepository {
  PatientSearchPage searchPage = const PatientSearchPage(items: [], totalCount: 0, limit: 1, offset: 0);
  Object? createException;
  int? duplicateWarningOnCreateIndex;

  int searchCallCount = 0;
  int createCallCount = 0;
  int archiveCallCount = 0;

  String? lastSearchQuery;
  PatientListScope? lastSearchScope;
  int? lastSearchLimit;

  final List<CreatePatientInput> createdInputs = [];
  final List<String> createdPatientIds = [];
  final List<String> createdBranchIds = [];
  final List<String> archivedPatientIds = [];

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
    lastSearchQuery = query;
    lastSearchScope = scope;
    lastSearchLimit = limit;
    return searchPage;
  }

  @override
  Future<CreatePatientResult> createPatient(CreatePatientInput input) async {
    createCallCount++;
    createdInputs.add(input);
    createdBranchIds.add(input.activeBranchId);

    if (createException != null) {
      throw createException!;
    }

    if (duplicateWarningOnCreateIndex != null && createCallCount - 1 == duplicateWarningOnCreateIndex) {
      if (!input.acknowledgeDuplicate) {
        throw RpcFailure(
          const RpcResult(success: false, errorCode: 'DUPLICATE_WARNING', errorMessage: 'Possible duplicate'),
        );
      }
    }

    final patientId = 'patient-$createCallCount';
    createdPatientIds.add(patientId);
    return CreatePatientResult(patientId: patientId, mrn: input.mrn ?? 'MRN-000000');
  }

  @override
  Future<void> archivePatient(String patientId) async {
    archiveCallCount++;
    archivedPatientIds.add(patientId);
  }

  @override
  Future<List<DuplicateCandidate>> checkDuplicates({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? excludePatientId,
  }) =>
      throw UnimplementedError();

  @override
  Future<PatientDetail> getPatient(String patientId) => throw UnimplementedError();

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) => throw UnimplementedError();

  @override
  Future<String> reassignPatientMrn({required String patientId, required String newMrn}) =>
      throw UnimplementedError();
}

class _FakeBranchRepository implements BranchRepository {
  _FakeBranchRepository({required this.branches});

  List<BranchListItem> branches;
  Object? listException;
  int listCalls = 0;
  final List<CreateBranchInput> createCalls = [];

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    listCalls++;
    if (listException != null) {
      throw listException!;
    }
    return branches;
  }

  @override
  Future<String> createBranch(CreateBranchInput input) async {
    createCalls.add(input);
    return _createdSecondBranchId;
  }

  @override
  Future<String> updateBranch(UpdateBranchInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) =>
      throw UnimplementedError();

  @override
  Future<RpcResult> deleteBranch({required String branchId}) => throw UnimplementedError();
}

class _FakeStaffAdminRepository implements StaffAdminRepository {
  _FakeStaffAdminRepository({required this.detail});

  StaffMemberDetail? detail;
  int fetchCalls = 0;
  final List<UpdateStaffMemberInput> updateCalls = [];

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) async {
    fetchCalls++;
    return detail;
  }

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) async {
    updateCalls.add(input);
    return input.staffMemberId;
  }

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) =>
      throw UnimplementedError();

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) =>
      throw UnimplementedError();

  @override
  Future<RpcResult> deleteStaffMember({required String staffMemberId}) => throw UnimplementedError();
}
