import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/theme_transition_controller.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_result.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/usecases/check_duplicates.dart';
import 'package:ai_clinic/features/patients/domain/usecases/get_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/patients/domain/usecases/update_patient.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_edit_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';

void main() {
  const patientId = '11111111-1111-4111-8111-111111111111';

  group('PatientEditNotifier', () {
    late _EditRepository repository;
    late PatientDetail currentDetail;
    late AuthSessionState authState;

    ProviderContainer createContainer({
      AuthSessionState? session,
      GlobalKey<NavigatorState>? navigatorKey,
      PatientDetail? initialDetail,
    }) {
      currentDetail = initialDetail ??
          samplePatientDetail(
            id: patientId,
            fullName: 'Test Patient',
            phone: '2012345678',
            updatedAt: DateTime.utc(2026, 3, 1),
          );
      repository.detail = currentDetail;
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => MutableAuthSessionNotifier(session ?? authState),
          ),
          rootNavigatorKeyProvider.overrideWithValue(
            navigatorKey ?? GlobalKey<NavigatorState>(),
          ),
          getPatientUseCaseProvider.overrideWith(
            (ref) => GetPatient(repository),
          ),
          patientDetailProvider(patientId).overrideWith(
            (ref) async => repository.getPatient(patientId),
          ),
          checkDuplicatesUseCaseProvider.overrideWith(
            (ref) => CheckDuplicates(repository),
          ),
          updatePatientUseCaseProvider.overrideWith(
            (ref) => UpdatePatient(repository),
          ),
          searchPatientsUseCaseProvider.overrideWith(
            (ref) => SearchPatients(repository),
          ),
        ],
      );
    }

    Future<PatientEditNotifier> readNotifier(ProviderContainer container) async {
      final notifier = container.read(patientEditProvider(patientId).notifier);
      await container.read(patientDetailProvider(patientId).future);
      return notifier;
    }

    PatientEditState readState(ProviderContainer container) {
      return container.read(patientEditProvider(patientId));
    }

    setUp(() {
      repository = _EditRepository();
      authState = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: const {'patients.view', 'patients.edit'}),
      );
    });

    test('starts with empty initial state before hydration', () {
      final container = createContainer();
      addTearDown(container.dispose);

      final state = readState(container);

      expect(state.values, PatientRegistrationForm.empty);
      expect(state.hydrated, isFalse);
      expect(state.expectedUpdatedAt, isNull);
    });

    test('hydrates from patientDetailProvider on first emission', () async {
      final detail = samplePatientDetail(
        id: patientId,
        fullName: 'Hydrated Patient',
        phone: '2098765432',
        gender: PatientGender.female,
        notes: 'Note text',
        branchName: 'Branch B',
        updatedAt: DateTime.utc(2026, 4, 10),
      );

      final container = createContainer(initialDetail: detail);
      addTearDown(container.dispose);

      await readNotifier(container);

      final state = readState(container);
      expect(state.hydrated, isTrue);
      expect(state.values.fullName, 'Hydrated Patient');
      expect(state.values.phone, '2098765432');
      expect(state.values.gender, PatientGender.female);
      expect(state.values.notes, 'Note text');
      expect(state.expectedUpdatedAt, DateTime.utc(2026, 4, 10));
      expect(state.branchName, 'Branch B');
    });

    test('ignores second detail emission once hydrated preserving user edits', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      notifier.updateField('fullName', 'Edited Name');

      currentDetail = currentDetail.copyWith(fullName: 'Server Overwrite');
      repository.detail = currentDetail;
      container.invalidate(patientDetailProvider(patientId));
      await container.read(patientDetailProvider(patientId).future);

      expect(readState(container).values.fullName, 'Edited Name');
      expect(readState(container).hydrated, isTrue);
    });

    test('re-hydrates from detail when staleUpdateOpen is true', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      notifier
        ..updateField('fullName', 'Edited Name')
        ..setStaleUpdateOpen(true);

      currentDetail = currentDetail.copyWith(fullName: 'Reloaded Patient');
      repository.detail = currentDetail;
      container.invalidate(patientDetailProvider(patientId));
      await container.read(patientDetailProvider(patientId).future);

      expect(readState(container).values.fullName, 'Reloaded Patient');
      expect(readState(container).hydrated, isTrue);
    });

    group('updateField', () {
      test('updates fullName and clears fullName error after hydration', () async {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = await readNotifier(container);

        notifier.updateField('fullName', '');
        await notifier.submit();
        expect(readState(container).errors.fullName, isNotNull);

        notifier.updateField('fullName', 'Updated Name');

        final state = readState(container);
        expect(state.values.fullName, 'Updated Name');
        expect(state.errors.fullName, isNull);
      });

      test('updates phone and clears phone error', () async {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = await readNotifier(container);

        notifier.updateField('phone', 'abc');
        await notifier.submit();

        notifier.updateField('phone', '2011111111');

        final state = readState(container);
        expect(state.values.phone, '2011111111');
        expect(state.errors.phone, isNull);
      });

      test('updates dateOfBirth and clears dateOfBirth error', () async {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = await readNotifier(container);
        final dob = DateTime.utc(1985, 12, 1);

        notifier.updateField('dateOfBirth', dob);

        expect(readState(container).values.dateOfBirth, dob);
        expect(readState(container).errors.dateOfBirth, isNull);
      });

      test('updates gender and clears gender error', () async {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = await readNotifier(container);

        notifier.updateField('gender', PatientGender.other);

        expect(readState(container).values.gender, PatientGender.other);
        expect(readState(container).errors.gender, isNull);
      });

      test('updates maritalStatus and clears maritalStatus error', () async {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = await readNotifier(container);

        notifier.updateField('maritalStatus', PatientMaritalStatus.divorced);

        expect(readState(container).values.maritalStatus, PatientMaritalStatus.divorced);
        expect(readState(container).errors.maritalStatus, isNull);
      });

      test('updates notes and clears notes error', () async {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = await readNotifier(container);

        notifier.updateField('notes', 'Updated notes');

        expect(readState(container).values.notes, 'Updated notes');
        expect(readState(container).errors.notes, isNull);
      });

      test('resets acknowledgedDuplicate to false when editing after acknowledgement', () async {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = await readNotifier(container);

        await notifier.saveAnyway();
        expect(readState(container).acknowledgedDuplicate, isTrue);

        notifier.updateField('fullName', 'Changed Again');

        expect(readState(container).acknowledgedDuplicate, isFalse);
      });
    });

    test('submit before hydration sets loading form error and skips RPC', () async {
      repository.detailDelay = const Duration(milliseconds: 100);

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(patientEditProvider(patientId).notifier);

      final result = await notifier.submit();

      expect(result, isFalse);
      expect(
        readState(container).errors.form,
        'Patient details are still loading. Try again.',
      );
      expect(repository.updateCallCount, 0);
    });

    test('submit with validation failures sets field errors and skips update', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      notifier.updateField('fullName', '');

      final result = await notifier.submit();

      expect(result, isFalse);
      final state = readState(container);
      expect(state.errors.fullName, "Enter the patient's full name.");
      expect(state.submitting, isFalse);
      expect(repository.updateCallCount, 0);
    });

    test('submit with duplicates opens dialog and skips update', () async {
      const candidate = DuplicateCandidate(
        id: '22222222-2222-4222-8222-222222222222',
        fullName: 'Other Patient',
        branchName: 'Branch A',
      );
      repository.duplicates = [candidate];

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      final result = await notifier.submit();

      expect(result, isFalse);
      final state = readState(container);
      expect(state.duplicateOpen, isTrue);
      expect(state.duplicateCandidates, [candidate]);
      expect(state.submitting, isFalse);
      expect(repository.checkDuplicatesCallCount, 1);
      expect(repository.lastCheckExcludePatientId, patientId);
      expect(repository.updateCallCount, 0);
    });

    test('submit success invalidates detail and list providers', () async {
      repository.nextSearchPage = const PatientSearchPage(
        items: [],
        totalCount: 0,
        limit: 20,
        offset: 0,
      );

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      await container.read(patientListProvider.future);
      final detailCallsBefore = repository.getPatientCallCount;
      final searchCallsBefore = repository.searchCallCount;

      final result = await notifier.submit();

      expect(result, isTrue);
      expect(readState(container).submitting, isFalse);

      await container.read(patientDetailProvider(patientId).future);
      await container.read(patientListProvider.future);

      expect(repository.getPatientCallCount, greaterThan(detailCallsBefore));
      expect(repository.searchCallCount, greaterThan(searchCallsBefore));
      expect(repository.updateCallCount, 1);
      expect(
        repository.lastUpdateInput?.expectedUpdatedAt,
        DateTime.utc(2026, 3, 1),
      );
    });

    test('submit success does not throw when navigator context is null', () async {
      final container = createContainer(navigatorKey: GlobalKey<NavigatorState>());
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      await expectLater(notifier.submit(), completion(isTrue));
      expect(readState(container).submitting, isFalse);
    });

    test('submit maps non-stale RpcFailure to form error', () async {
      repository.updateException = RpcFailure(
        const RpcResult(success: false, errorCode: 'FORBIDDEN', errorMessage: 'denied'),
      );

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      final result = await notifier.submit();

      expect(result, isFalse);
      expect(
        readState(container).errors.form,
        'You do not have permission to perform this action.',
      );
      expect(readState(container).submitting, isFalse);
      expect(readState(container).staleUpdateOpen, isFalse);
    });

    test('submit stale RpcFailure opens stale update dialog', () async {
      repository.updateException = RpcFailure(
        const RpcResult(success: false, errorCode: 'STALE_PATIENT', errorMessage: 'stale'),
      );

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      final result = await notifier.submit();

      expect(result, isFalse);
      final state = readState(container);
      expect(state.staleUpdateOpen, isTrue);
      expect(state.submitting, isFalse);
      expect(state.errors, PatientFormErrors.empty);
    });

    test('confirmStaleReload clears hydration and refetches detail', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      notifier
        ..setStaleUpdateOpen(true)
        ..updateField('fullName', 'Stale Edit');
      final callsBefore = repository.getPatientCallCount;

      currentDetail = currentDetail.copyWith(fullName: 'Fresh From Server');
      repository.detail = currentDetail;
      notifier.confirmStaleReload();

      expect(readState(container).hydrated, isFalse);
      expect(readState(container).staleUpdateOpen, isFalse);

      await container.read(patientDetailProvider(patientId).future);

      expect(repository.getPatientCallCount, greaterThan(callsBefore));
      expect(readState(container).hydrated, isTrue);
      expect(readState(container).values.fullName, 'Fresh From Server');
    });

    test('saveAnyway bypasses duplicate check and updates with acknowledgement', () async {
      const candidate = DuplicateCandidate(
        id: '22222222-2222-4222-8222-222222222222',
        fullName: 'Other Patient',
        branchName: 'Branch A',
      );
      repository.duplicates = [candidate];

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      await notifier.submit();
      expect(repository.updateCallCount, 0);

      final result = await notifier.saveAnyway();

      expect(result, isTrue);
      expect(readState(container).acknowledgedDuplicate, isTrue);
      expect(readState(container).duplicateOpen, isFalse);
      expect(repository.checkDuplicatesCallCount, 1);
      expect(repository.updateCallCount, 1);
      expect(repository.lastUpdateInput?.acknowledgeDuplicate, isTrue);
    });

    test('openExistingPatient sets pendingOpenPatientId and closes duplicate dialog', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      notifier
        ..setDuplicateOpen(true)
        ..openExistingPatient('22222222-2222-4222-8222-222222222222');

      final state = readState(container);
      expect(state.pendingOpenPatientId, '22222222-2222-4222-8222-222222222222');
      expect(state.duplicateOpen, isFalse);
    });

    test('clearPendingOpenPatient clears pendingOpenPatientId', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      notifier.openExistingPatient('22222222-2222-4222-8222-222222222222');
      notifier.clearPendingOpenPatient();

      expect(readState(container).pendingOpenPatientId, isNull);
    });

    test('reset returns to initial state', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      notifier
        ..updateField('fullName', 'Changed')
        ..setDuplicateOpen(true)
        ..openExistingPatient('22222222-2222-4222-8222-222222222222');
      notifier.reset();

      expect(readState(container), const PatientEditState());
    });

    test('setDuplicateOpen toggles duplicateOpen', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      notifier.setDuplicateOpen(true);
      expect(readState(container).duplicateOpen, isTrue);

      notifier.setDuplicateOpen(false);
      expect(readState(container).duplicateOpen, isFalse);
    });

    test('setStaleUpdateOpen toggles staleUpdateOpen', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      notifier.setStaleUpdateOpen(true);
      expect(readState(container).staleUpdateOpen, isTrue);

      notifier.setStaleUpdateOpen(false);
      expect(readState(container).staleUpdateOpen, isFalse);
    });

    test('submitting is true during in-flight submit and false after', () async {
      repository.updateDelay = const Duration(milliseconds: 50);

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      final future = notifier.submit();
      expect(readState(container).submitting, isTrue);

      await future;
      expect(readState(container).submitting, isFalse);
    });

  // ignore: lines_longer_than_80_chars
    test('concurrent submit calls both reach update (no in-flight guard)', () async {
      repository.updateDelay = const Duration(milliseconds: 50);

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = await readNotifier(container);

      final first = notifier.submit();
      final second = notifier.submit();
      await Future.wait([first, second]);

      expect(repository.updateCallCount, 2);
    });
  });
}

class _EditRepository implements PatientRepository {
  PatientDetail? detail;
  Duration detailDelay = Duration.zero;
  List<DuplicateCandidate> duplicates = const [];
  Duration updateDelay = Duration.zero;
  Object? updateException;
  PatientSearchPage nextSearchPage = const PatientSearchPage(
    items: [],
    totalCount: 0,
    limit: 20,
    offset: 0,
  );

  int getPatientCallCount = 0;
  int checkDuplicatesCallCount = 0;
  int updateCallCount = 0;
  int searchCallCount = 0;
  String? lastCheckExcludePatientId;
  UpdatePatientInput? lastUpdateInput;

  @override
  Future<PatientDetail> getPatient(String patientId) async {
    getPatientCallCount++;
    if (detailDelay > Duration.zero) {
      await Future<void>.delayed(detailDelay);
    }
    if (detail != null) {
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
    checkDuplicatesCallCount++;
    lastCheckExcludePatientId = excludePatientId;
    return duplicates;
  }

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) async {
    updateCallCount++;
    lastUpdateInput = input;
    if (updateDelay > Duration.zero) {
      await Future<void>.delayed(updateDelay);
    }
    if (updateException != null) {
      throw updateException!;
    }
    return DateTime.utc(2026, 5, 1);
  }

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
    return nextSearchPage;
  }

  @override
  Future<void> archivePatient(String patientId) => throw UnimplementedError();

  @override
  Future<CreatePatientResult> createPatient(CreatePatientInput input) =>
      throw UnimplementedError();

  @override
  Future<String> reassignPatientMrn({required String patientId, required String newMrn}) =>
      throw UnimplementedError();
}