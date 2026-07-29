import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
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
import 'package:ai_clinic/features/patients/domain/usecases/create_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_registration_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('PatientRegistrationNotifier', () {
    late _RegistrationRepository repository;
    late AuthSessionState authState;

    ProviderContainer createContainer({AuthSessionState? session}) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => MutableAuthSessionNotifier(session ?? authState),
          ),
          checkDuplicatesUseCaseProvider.overrideWith(
            (ref) => CheckDuplicates(repository),
          ),
          createPatientUseCaseProvider.overrideWith(
            (ref) => CreatePatient(repository),
          ),
        ],
      );
    }

    PatientRegistrationNotifier readNotifier(ProviderContainer container) {
      return container.read(patientRegistrationProvider.notifier);
    }

    PatientRegistrationState readState(ProviderContainer container) {
      return container.read(patientRegistrationProvider);
    }

    void fillValidForm(PatientRegistrationNotifier notifier) {
      notifier
        ..updateField('fullName', 'Jane Doe')
        ..updateField('phone', '2012345678');
    }

    setUp(() {
      repository = _RegistrationRepository();
      authState = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(),
      );
    });

    test('starts with empty initial state', () {
      final container = createContainer();
      addTearDown(container.dispose);

      final state = readState(container);

      expect(state.values, PatientRegistrationForm.empty);
      expect(state.errors, PatientFormErrors.empty);
      expect(state.submitting, isFalse);
      expect(state.duplicateCandidates, isEmpty);
      expect(state.duplicateOpen, isFalse);
      expect(state.acknowledgedDuplicate, isFalse);
      expect(state.pendingOpenPatientId, isNull);
    });

    group('updateField', () {
      test('updates fullName and clears fullName error', () {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = readNotifier(container);

        notifier.submit();
        expect(readState(container).errors.fullName, isNotNull);

        notifier.updateField('fullName', 'Jane Doe');

        final state = readState(container);
        expect(state.values.fullName, 'Jane Doe');
        expect(state.errors.fullName, isNull);
      });

      test('updates phone and clears phone error', () {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = readNotifier(container);

        notifier.submit();
        notifier.updateField('phone', '2012345678');

        final state = readState(container);
        expect(state.values.phone, '2012345678');
        expect(state.errors.phone, isNull);
      });

      test('updates dateOfBirth and clears dateOfBirth error', () {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = readNotifier(container);
        final dob = DateTime.utc(1990, 5, 15);

        notifier.updateField('dateOfBirth', dob);

        final state = readState(container);
        expect(state.values.dateOfBirth, dob);
        expect(state.errors.dateOfBirth, isNull);
      });

      test('updates gender and clears gender error', () {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = readNotifier(container);

        notifier.updateField('gender', PatientGender.female);

        final state = readState(container);
        expect(state.values.gender, PatientGender.female);
        expect(state.errors.gender, isNull);
      });

      test('updates maritalStatus and clears maritalStatus error', () {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = readNotifier(container);

        notifier.updateField('maritalStatus', PatientMaritalStatus.married);

        final state = readState(container);
        expect(state.values.maritalStatus, PatientMaritalStatus.married);
        expect(state.errors.maritalStatus, isNull);
      });

      test('updates notes and clears notes error', () {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = readNotifier(container);

        notifier.updateField('notes', 'Allergic to penicillin');

        final state = readState(container);
        expect(state.values.notes, 'Allergic to penicillin');
        expect(state.errors.notes, isNull);
      });

      test('resets acknowledgedDuplicate to false when editing after acknowledgement', () async {
        final container = createContainer();
        addTearDown(container.dispose);
        final notifier = readNotifier(container);
        fillValidForm(notifier);

        await notifier.registerAnyway();
        expect(readState(container).acknowledgedDuplicate, isTrue);

        notifier.updateField('fullName', 'Jane Smith');

        expect(readState(container).acknowledgedDuplicate, isFalse);
      });
    });

    test('submit without active branch sets form error and skips RPC', () async {
      final container = createContainer(
        session: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(branchIds: const [], activeBranchId: null),
        ),
      );
      addTearDown(container.dispose);
      final notifier = readNotifier(container);
      fillValidForm(notifier);

      final result = await notifier.submit();

      expect(result, isNull);
      expect(
        readState(container).errors.form,
        'Select an active branch before registering a patient.',
      );
      expect(repository.checkDuplicatesCallCount, 0);
      expect(repository.createCallCount, 0);
    });

    test('submit with validation failures sets field errors and skips create', () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);

      final result = await notifier.submit();

      expect(result, isNull);
      final state = readState(container);
      expect(state.errors.fullName, "Enter the patient's full name.");
      expect(state.errors.phone, 'Mobile number is required.');
      expect(state.submitting, isFalse);
      expect(repository.checkDuplicatesCallCount, 0);
      expect(repository.createCallCount, 0);
    });

    test('submit with duplicates opens dialog and skips create', () async {
      const candidate = DuplicateCandidate(
        id: '22222222-2222-4222-8222-222222222222',
        fullName: 'Jane Doe',
        branchName: 'Branch A',
        phone: '2012345678',
      );
      repository.duplicates = [candidate];

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);
      fillValidForm(notifier);

      final result = await notifier.submit();

      expect(result, isNull);
      final state = readState(container);
      expect(state.duplicateOpen, isTrue);
      expect(state.duplicateCandidates, [candidate]);
      expect(state.submitting, isFalse);
      expect(repository.checkDuplicatesCallCount, 1);
      expect(repository.createCallCount, 0);
    });

    test('submit success returns CreatePatientResult and clears submitting', () async {
      const expected = CreatePatientResult(
        patientId: '33333333-3333-4333-8333-333333333333',
        mrn: 'MRN-000042',
      );
      repository.createResult = expected;

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);
      fillValidForm(notifier);

      final result = await notifier.submit();

      expect(result, expected);
      expect(readState(container).submitting, isFalse);
      expect(repository.createCallCount, 1);
    });

    test('submit maps RpcFailure to form error', () async {
      repository.createException = RpcFailure(
        const RpcResult(success: false, errorCode: 'FORBIDDEN', errorMessage: 'denied'),
      );

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);
      fillValidForm(notifier);

      final result = await notifier.submit();

      expect(result, isNull);
      expect(
        readState(container).errors.form,
        'You do not have permission to perform this action.',
      );
      expect(readState(container).submitting, isFalse);
    });

    test('submit maps generic exception to form error', () async {
      repository.createException = StateError('network down');

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);
      fillValidForm(notifier);

      final result = await notifier.submit();

      expect(result, isNull);
      expect(
        readState(container).errors.form,
        'Could not register the patient. Try again.',
      );
      expect(readState(container).submitting, isFalse);
    });

    test('registerAnyway bypasses duplicate check and creates with acknowledgement', () async {
      const candidate = DuplicateCandidate(
        id: '22222222-2222-4222-8222-222222222222',
        fullName: 'Jane Doe',
        branchName: 'Branch A',
      );
      repository.duplicates = [candidate];
      const expected = CreatePatientResult(
        patientId: '44444444-4444-4444-8444-444444444444',
        mrn: 'MRN-000099',
      );
      repository.createResult = expected;

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);
      fillValidForm(notifier);

      await notifier.submit();
      expect(repository.createCallCount, 0);

      final result = await notifier.registerAnyway();

      expect(result, expected);
      expect(readState(container).acknowledgedDuplicate, isTrue);
      expect(readState(container).duplicateOpen, isFalse);
      expect(repository.checkDuplicatesCallCount, 1);
      expect(repository.createCallCount, 1);
      expect(repository.lastCreateInput?.acknowledgeDuplicate, isTrue);
    });

    test('openExistingPatient sets pendingOpenPatientId and closes duplicate dialog', () {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);

      notifier.setDuplicateOpen(true);
      notifier.openExistingPatient('11111111-1111-4111-8111-111111111111');

      final state = readState(container);
      expect(state.pendingOpenPatientId, '11111111-1111-4111-8111-111111111111');
      expect(state.duplicateOpen, isFalse);
    });

    test('clearPendingOpenPatient clears pendingOpenPatientId', () {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);

      notifier.openExistingPatient('11111111-1111-4111-8111-111111111111');
      notifier.clearPendingOpenPatient();

      expect(readState(container).pendingOpenPatientId, isNull);
    });

    test('reset returns to initial state', () {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);

      notifier
        ..updateField('fullName', 'Jane Doe')
        ..setDuplicateOpen(true)
        ..openExistingPatient('11111111-1111-4111-8111-111111111111');
      notifier.reset();

      expect(readState(container), const PatientRegistrationState());
    });

    test('setDuplicateOpen toggles duplicateOpen', () {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);

      notifier.setDuplicateOpen(true);
      expect(readState(container).duplicateOpen, isTrue);

      notifier.setDuplicateOpen(false);
      expect(readState(container).duplicateOpen, isFalse);
    });

    test('submitting is true during in-flight submit and false after', () async {
      repository.createDelay = const Duration(milliseconds: 50);

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);
      fillValidForm(notifier);

      final future = notifier.submit();
      expect(readState(container).submitting, isTrue);

      await future;
      expect(readState(container).submitting, isFalse);
    });

  // ignore: lines_longer_than_80_chars
    test('concurrent submit calls both reach create (no in-flight guard)', () async {
      repository.createDelay = const Duration(milliseconds: 50);

      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = readNotifier(container);
      fillValidForm(notifier);

      final first = notifier.submit();
      final second = notifier.submit();
      await Future.wait([first, second]);

      expect(repository.createCallCount, 2);
    });
  });
}

class _RegistrationRepository implements PatientRepository {
  List<DuplicateCandidate> duplicates = const [];
  CreatePatientResult createResult = const CreatePatientResult(
    patientId: '33333333-3333-4333-8333-333333333333',
    mrn: 'MRN-000001',
  );
  Duration createDelay = Duration.zero;
  Object? createException;

  int checkDuplicatesCallCount = 0;
  int createCallCount = 0;
  CreatePatientInput? lastCreateInput;

  @override
  Future<List<DuplicateCandidate>> checkDuplicates({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? excludePatientId,
  }) async {
    checkDuplicatesCallCount++;
    return duplicates;
  }

  @override
  Future<CreatePatientResult> createPatient(CreatePatientInput input) async {
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
  Future<void> archivePatient(String patientId) => throw UnimplementedError();

  @override
  Future<PatientDetail> getPatient(String patientId) => throw UnimplementedError();

  @override
  Future<PatientSearchPage> searchPatients({
    String? query,
    required PatientListScope scope,
    String? branchId,
    int limit = 25,
    int offset = 0,
    PatientLastVisitFilter lastVisitFilter = PatientLastVisitFilter.any,
    PatientSortField sortField = PatientSortField.nameAsc,
  }) =>
      throw UnimplementedError();

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) => throw UnimplementedError();

  @override
  Future<String> reassignPatientMrn({required String patientId, required String newMrn}) =>
      throw UnimplementedError();
}
