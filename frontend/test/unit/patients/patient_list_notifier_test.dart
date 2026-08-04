import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_result.dart';
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
import '../../helpers/patient_test_support.dart';

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

    test('M4 / PL-F-027: reloads when active branch changes', () async {
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

  group('PatientListNotifier filter and sort wiring (PL-F)', () {
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
      repository.nextPage = const PatientSearchPage(items: [], totalCount: 0, limit: 20, offset: 0);
    });

    test('PL-F-017: forwards never last-visit filter', () async {
      final providerContainer = createContainer();
      addTearDown(providerContainer.dispose);

      await providerContainer
          .read(patientListProvider.notifier)
          .applyFilters(const PatientListFilters(lastVisitFilter: PatientLastVisitFilter.never));

      expect(repository.lastLastVisitFilter, PatientLastVisitFilter.never);
    });

    test('PL-F-018: forwards last 30 days filter', () async {
      final providerContainer = createContainer();
      addTearDown(providerContainer.dispose);

      await providerContainer
          .read(patientListProvider.notifier)
          .applyFilters(const PatientListFilters(lastVisitFilter: PatientLastVisitFilter.last30Days));

      expect(repository.lastLastVisitFilter, PatientLastVisitFilter.last30Days);
    });

    test('PL-F-019: forwards last 90 days filter', () async {
      final providerContainer = createContainer();
      addTearDown(providerContainer.dispose);

      await providerContainer
          .read(patientListProvider.notifier)
          .applyFilters(const PatientListFilters(lastVisitFilter: PatientLastVisitFilter.last90Days));

      expect(repository.lastLastVisitFilter, PatientLastVisitFilter.last90Days);
    });

    test('PL-F-020: forwards over 90 days filter', () async {
      final providerContainer = createContainer();
      addTearDown(providerContainer.dispose);

      await providerContainer
          .read(patientListProvider.notifier)
          .applyFilters(const PatientListFilters(lastVisitFilter: PatientLastVisitFilter.over90Days));

      expect(repository.lastLastVisitFilter, PatientLastVisitFilter.over90Days);
    });

    test('PL-F-021: forwards name descending sort', () async {
      final providerContainer = createContainer();
      addTearDown(providerContainer.dispose);

      await providerContainer
          .read(patientListProvider.notifier)
          .applyFilters(const PatientListFilters(sortField: PatientSortField.nameDesc));

      expect(repository.lastSortField, PatientSortField.nameDesc);
    });

    test('PL-F-022: forwards last visit ascending sort', () async {
      final providerContainer = createContainer();
      addTearDown(providerContainer.dispose);

      await providerContainer
          .read(patientListProvider.notifier)
          .applyFilters(const PatientListFilters(sortField: PatientSortField.lastVisitAsc));

      expect(repository.lastSortField, PatientSortField.lastVisitAsc);
    });

    test('PL-F-023: forwards combined never filter and name asc sort', () async {
      final providerContainer = createContainer();
      addTearDown(providerContainer.dispose);

      await providerContainer
          .read(patientListProvider.notifier)
          .applyFilters(
            const PatientListFilters(
              lastVisitFilter: PatientLastVisitFilter.never,
              sortField: PatientSortField.nameAsc,
            ),
          );

      expect(repository.lastLastVisitFilter, PatientLastVisitFilter.never);
      expect(repository.lastSortField, PatientSortField.nameAsc);
    });

    test('PL-F-014/015: forwards organization scope for all-branches filter', () async {
      final providerContainer = createContainer();
      addTearDown(providerContainer.dispose);

      await providerContainer
          .read(patientListProvider.notifier)
          .applyFilters(const PatientListFilters(branchId: PatientListFilters.allBranchesSentinel));

      expect(repository.lastScope, PatientListScope.allBranches);
      expect(repository.lastBranchId, isNull);
    });
  });

  group('PatientListNotifier list state', () {
    late FakePatientRepository repository;

    ProviderContainer createContainer({AuthSessionNotifier Function()? authFactory}) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(authFactory ?? _PatientsAuthNotifier.new),
          searchPatientsUseCaseProvider.overrideWith((ref) => SearchPatients(repository)),
        ],
      );
    }

    setUp(() {
      repository = FakePatientRepository(
        patients: samplePatientList(count: 2),
      );
    });

    test('initial build uses default filters and issues exactly one search', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final state = await container.read(patientListProvider.future);

      expect(state.filters, const PatientListFilters());
      expect(repository.searchCallCount, 1);
      expect(repository.lastOffset, 0);
      expect(repository.lastLimit, 20);
      expect(repository.lastScope, PatientListScope.thisBranch);
    });

    test('permission gate returns empty state without issuing search', () async {
      final container = createContainer(authFactory: _NoPatientListAuthNotifier.new);
      addTearDown(container.dispose);

      final state = await container.read(patientListProvider.future);

      expect(state.rows, isEmpty);
      expect(state.totalCount, 0);
      expect(repository.searchCallCount, 0);
    });

    test('invalid search term sets searchHint and skips search', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(patientListProvider.notifier);

      await container.read(patientListProvider.future);
      final callsBefore = repository.searchCallCount;

      await notifier.applyFilters(const PatientListFilters(searchText: 'ab'));

      final state = container.read(patientListProvider).requireValue;
      expect(state.rows, isEmpty);
      expect(state.totalCount, 0);
      expect(state.searchHint, 'Enter at least 3 characters to search by name.');
      expect(repository.searchCallCount, callsBefore);
    });

    test('this-branch scope with missing activeBranchId returns empty state without search', () async {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(_NoActiveBranchAuthNotifier.new),
          searchPatientsUseCaseProvider.overrideWith((ref) => SearchPatients(repository)),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(patientListProvider.future);

      expect(state.rows, isEmpty);
      expect(state.totalCount, 0);
      expect(repository.searchCallCount, 0);
    });

    test('forwards valid search text as query argument', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      await container.read(patientListProvider.future);
      final callsBefore = repository.searchCallCount;

      await container
          .read(patientListProvider.notifier)
          .applyFilters(const PatientListFilters(searchText: 'Sara'));

      expect(repository.lastQuery, 'Sara');
      expect(repository.searchCallCount, callsBefore + 1);
    });

    test('page 1 uses offset 0', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      await container.read(patientListProvider.notifier).applyFilters(const PatientListFilters(page: 1, pageSize: 20));

      expect(repository.lastOffset, 0);
      expect(repository.lastLimit, 20);
    });

    test('page 2 with pageSize 20 uses offset 20', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      await container
          .read(patientListProvider.notifier)
          .applyFilters(const PatientListFilters(page: 2, pageSize: 20));

      expect(repository.lastOffset, 20);
      expect(repository.lastLimit, 20);
    });

    test('empty server page is preserved in UI state', () async {
      repository = FakePatientRepository(patients: const []);
      final container = createContainer();
      addTearDown(container.dispose);

      final state = await container.read(patientListProvider.future);

      expect(state.rows, isEmpty);
      expect(state.totalCount, 0);
    });

    test('last page beyond totalCount returns empty rows', () async {
      repository = FakePatientRepository(patients: samplePatientList(count: 5));
      final container = createContainer();
      addTearDown(container.dispose);

      await container
          .read(patientListProvider.notifier)
          .applyFilters(const PatientListFilters(page: 2, pageSize: 20));

      final state = container.read(patientListProvider).requireValue;
      expect(state.rows, isEmpty);
      expect(state.totalCount, 5);
      expect(repository.lastOffset, 20);
    });

    test('search error surfaces as AsyncValue error then reload recovers', () async {
      final failingRepository = _ToggleSearchPatientRepository(
        patients: samplePatientList(count: 1),
      );
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(_PatientsAuthNotifier.new),
          searchPatientsUseCaseProvider.overrideWith((ref) => SearchPatients(failingRepository)),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(patientListProvider.notifier);

      await container.read(patientListProvider.future);
      final callsBefore = failingRepository.searchCallCount;
      failingRepository.throwOnNextSearch = true;
      await notifier.applyFilters(const PatientListFilters(searchText: 'Patient'));
      expect(container.read(patientListProvider).hasError, isTrue);

      await notifier.reload();

      final state = container.read(patientListProvider).requireValue;
      expect(state.rows, hasLength(1));
      expect(container.read(patientListProvider).hasError, isFalse);
      // Failed search increments once; successful reload increments twice (override + super).
      expect(failingRepository.searchCallCount, callsBefore + 3);
    });

    test('reload re-issues search with same filters', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(patientListProvider.notifier);

      await container.read(patientListProvider.future);
      expect(repository.searchCallCount, 1);

      await notifier.applyFilters(const PatientListFilters(searchText: 'Patient', page: 2, pageSize: 10));
      expect(repository.searchCallCount, 2);

      await notifier.reload();
      expect(repository.searchCallCount, 3);
      expect(repository.lastQuery, 'Patient');
      expect(repository.lastOffset, 10);
      expect(repository.lastLimit, 10);
    });

    test(
      'concurrent applyFilters keeps the last-applied filters when earlier response is slower',
      () async {
        final delayedRepository = _SequentialDelayPatientRepository(
          delays: const [Duration(milliseconds: 200), Duration.zero],
        );
        final container = ProviderContainer(
          overrides: [
            authSessionProvider.overrideWith(_PatientsAuthNotifier.new),
            searchPatientsUseCaseProvider.overrideWith((ref) => SearchPatients(delayedRepository)),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(patientListProvider.notifier);

        await container.read(patientListProvider.future);
        final callsBefore = delayedRepository.searchCallCount;

        final first = notifier.applyFilters(const PatientListFilters(searchText: 'Alpha'));
        final second = notifier.applyFilters(const PatientListFilters(searchText: 'Beta'));
        await Future.wait([first, second]);

        final state = container.read(patientListProvider).requireValue;
        expect(state.filters.searchText, 'Beta');
        expect(state.rows.single.item.fullName, contains('Beta'));
        expect(delayedRepository.searchCallCount, callsBefore + 2);
      },
    );
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
  PatientListScope? lastScope;
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
    lastScope = scope;
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
  Future<CreatePatientResult> createPatient(CreatePatientInput input) => throw UnimplementedError();

  @override
  Future<PatientDetail> getPatient(String patientId) => throw UnimplementedError();

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) => throw UnimplementedError();

  @override
  Future<String> reassignPatientMrn({required String patientId, required String newMrn}) => throw UnimplementedError();
<<<<<<< HEAD
=======
}

class _NoPatientListAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: const {}),
  );
}

class _NoActiveBranchAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(branchIds: const [], activeBranchId: null),
  );
}

class _ToggleSearchPatientRepository extends FakePatientRepository {
  _ToggleSearchPatientRepository({super.patients});

  bool throwOnNextSearch = false;

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
    if (throwOnNextSearch) {
      throwOnNextSearch = false;
      throw StateError('search failed');
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

class _SequentialDelayPatientRepository implements PatientRepository {
  _SequentialDelayPatientRepository({required List<Duration> delays}) : _delays = delays;

  final List<Duration> _delays;
  int _callIndex = 0;
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
    final delay = _callIndex < _delays.length ? _delays[_callIndex] : Duration.zero;
    _callIndex++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    final label = query ?? 'browse';
    return PatientSearchPage(
      items: [
        PatientListItem(
          id: 'patient-$label',
          fullName: 'Result for $label',
          registeringBranchId: testBranchAId,
          registeringBranchName: 'Branch A',
        ),
      ],
      totalCount: 1,
      limit: limit,
      offset: offset,
    );
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
  Future<CreatePatientResult> createPatient(CreatePatientInput input) => throw UnimplementedError();

  @override
  Future<PatientDetail> getPatient(String patientId) => throw UnimplementedError();

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) => throw UnimplementedError();

  @override
  Future<String> reassignPatientMrn({required String patientId, required String newMrn}) => throw UnimplementedError();
>>>>>>> master
}

class _NoPatientListAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: const {}),
  );
}

class _NoActiveBranchAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(branchIds: const [], activeBranchId: null),
  );
}

class _ToggleSearchPatientRepository extends FakePatientRepository {
  _ToggleSearchPatientRepository({super.patients});

  bool throwOnNextSearch = false;

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
    if (throwOnNextSearch) {
      throwOnNextSearch = false;
      throw StateError('search failed');
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

class _SequentialDelayPatientRepository implements PatientRepository {
  _SequentialDelayPatientRepository({required List<Duration> delays}) : _delays = delays;

  final List<Duration> _delays;
  int _callIndex = 0;
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
    final delay = _callIndex < _delays.length ? _delays[_callIndex] : Duration.zero;
    _callIndex++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    final label = query ?? 'browse';
    return PatientSearchPage(
      items: [
        PatientListItem(
          id: 'patient-$label',
          fullName: 'Result for $label',
          registeringBranchId: testBranchAId,
          registeringBranchName: 'Branch A',
        ),
      ],
      totalCount: 1,
      limit: limit,
      offset: offset,
    );
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
  Future<CreatePatientResult> createPatient(CreatePatientInput input) => throw UnimplementedError();

  @override
  Future<PatientDetail> getPatient(String patientId) => throw UnimplementedError();

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) => throw UnimplementedError();

  @override
  Future<String> reassignPatientMrn({required String patientId, required String newMrn}) => throw UnimplementedError();
}
