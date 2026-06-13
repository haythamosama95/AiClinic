import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('PatientListNotifier high-severity regressions', () {
    late _TrackingPatientRepository repository;

    ProviderContainer createContainer() {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(_PatientsAuthNotifier.new),
          searchPatientsUseCaseProvider.overrideWith((ref) => SearchPatients(repository)),
        ],
      );
    }

    setUp(() {
      repository = _TrackingPatientRepository();
    });

    test('H2: forwards last visit filter and sort to search_patients', () async {
      repository.nextPage = const PatientSearchPage(items: [], totalCount: 0, limit: 20, offset: 0);

      final providerContainer = createContainer();
      addTearDown(providerContainer.dispose);

      final notifier = providerContainer.read(patientListProvider.notifier);
      await notifier.applyFilters(
        const PatientListFilters(lastVisitFilter: PatientLastVisitFilter.never, sortField: PatientSortField.nameDesc),
      );

      expect(repository.lastLastVisitFilter, PatientLastVisitFilter.never);
      expect(repository.lastSortField, PatientSortField.nameDesc);
    });

    test('H2: preserves server row count and total_count without client-side shrinking', () async {
      repository.nextPage = PatientSearchPage(
        items: [
          PatientListItem(
            id: 'p1',
            fullName: 'Recent Visitor',
            registeringBranchId: '00000000-0000-4000-8000-000000000001',
            registeringBranchName: 'Main',
            lastVisitAt: DateTime.utc(2026, 5, 1),
          ),
          PatientListItem(
            id: 'p2',
            fullName: 'Old Visitor',
            registeringBranchId: '00000000-0000-4000-8000-000000000001',
            registeringBranchName: 'Main',
            lastVisitAt: DateTime.utc(2024, 1, 1),
          ),
        ],
        totalCount: 42,
        limit: 20,
        offset: 0,
      );

      final providerContainer = createContainer();
      addTearDown(providerContainer.dispose);

      final notifier = providerContainer.read(patientListProvider.notifier);
      await notifier.applyFilters(const PatientListFilters(lastVisitFilter: PatientLastVisitFilter.over90Days));

      final state = providerContainer.read(patientListProvider).requireValue;
      expect(state.rows, hasLength(2));
      expect(state.totalCount, 42);
      expect(repository.lastLastVisitFilter, PatientLastVisitFilter.over90Days);
    });
  });

  group('PatientListNotifier medium-severity regressions', () {
    late _TrackingPatientRepository repository;

    ProviderContainer createContainer(_SwitchablePatientsAuthNotifier auth) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => auth),
          searchPatientsUseCaseProvider.overrideWith((ref) => SearchPatients(repository)),
        ],
      );
    }

    setUp(() {
      repository = _TrackingPatientRepository();
      repository.nextPage = const PatientSearchPage(items: [], totalCount: 0, limit: 20, offset: 0);
    });

    test('M4: reloads when active branch changes', () async {
      const branchA = '00000000-0000-4000-8000-000000000001';
      const branchB = '00000000-0000-4000-8000-000000000002';
      final auth = _SwitchablePatientsAuthNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(branchIds: [branchA, branchB], activeBranchId: branchA),
        ),
      );

      final providerContainer = createContainer(auth);
      addTearDown(providerContainer.dispose);

      await providerContainer.read(patientListProvider.future);
      expect(repository.lastBranchId, branchA);
      expect(repository.searchCallCount, 1);

      auth.setActiveBranch(branchB);
      await providerContainer.read(patientListProvider.future);

      expect(repository.searchCallCount, 2);
      expect(repository.lastBranchId, branchB);
    });
  });
}

class _PatientsAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() =>
      AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext());
}

class _SwitchablePatientsAuthNotifier extends TestAuthSessionNotifier {
  _SwitchablePatientsAuthNotifier(AuthSessionState session) : _session = session;

  AuthSessionState _session;

  @override
  AuthSessionState build() => _session;

  @override
  void setActiveBranch(String branchId) {
    final context = _session.context;
    if (context == null) {
      return;
    }
    _session = _session.copyWith(context: context.copyWith(activeBranchId: branchId));
    state = _session;
  }
}

class _TrackingPatientRepository implements PatientRepository {
  PatientSearchPage nextPage = const PatientSearchPage(items: [], totalCount: 0, limit: 20, offset: 0);

  PatientLastVisitFilter? lastLastVisitFilter;
  PatientSortField? lastSortField;
  String? lastBranchId;
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
    lastLastVisitFilter = lastVisitFilter;
    lastSortField = sortField;
    lastBranchId = branchId;
    return nextPage;
  }

  @override
  Future<void> archivePatient(String patientId) => throw UnimplementedError();

  @override
  Future<List<DuplicateCandidate>> checkDuplicates({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? excludePatientId,
  }) => throw UnimplementedError();

  @override
  Future<String> createPatient(CreatePatientInput input) => throw UnimplementedError();

  @override
  Future<PatientDetail> getPatient(String patientId) => throw UnimplementedError();

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) => throw UnimplementedError();
}
