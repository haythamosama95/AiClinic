import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_result.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/usecases/get_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';

void main() {
  group('patientDetailProvider', () {
    const patientId = '11111111-1111-4111-8111-111111111111';
    late PatientDetail detail;

    ProviderContainer createContainer({
      required MutableAuthSessionNotifier auth,
      required PatientRepository repository,
    }) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => auth),
          getPatientUseCaseProvider.overrideWith((ref) => GetPatient(repository)),
        ],
      );
    }

    setUp(() {
      detail = samplePatientDetail(id: patientId);
    });

    test('returns patient detail when permission is granted', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(),
        ),
      );
      final repository = FakePatientRepository(detail: detail);
      final container = createContainer(auth: auth, repository: repository);
      addTearDown(container.dispose);

      final result = await container.read(patientDetailProvider(patientId).future);

      expect(result, detail);
      expect(result.id, patientId);
    });

    test('throws StateError when permission is denied', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: const {}),
        ),
      );
      final container = createContainer(
        auth: auth,
        repository: FakePatientRepository(),
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(patientDetailProvider(patientId).future),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'You do not have permission to view this patient.',
          ),
        ),
      );
    });

    test('rebuilds to error when permission is revoked', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(),
        ),
      );
      final repository = FakePatientRepository(detail: detail);
      final container = createContainer(auth: auth, repository: repository);
      addTearDown(container.dispose);

      final subscription = container.listen(
        patientDetailProvider(patientId),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container.read(patientDetailProvider(patientId).future);
      expect(container.read(patientDetailProvider(patientId)).hasValue, isTrue);

      auth.replace(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(permissions: const {}),
        ),
      );
      await container.read(patientDetailProvider(patientId).future);
      final asyncValue = container.read(patientDetailProvider(patientId));

      expect(asyncValue.hasError, isTrue);
      expect(asyncValue.error, isA<StateError>());
    });

    test('propagates use-case failures', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(),
        ),
      );
      final container = createContainer(
        auth: auth,
        repository: _ThrowingGetPatientRepository(),
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(patientDetailProvider(patientId).future),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _ThrowingGetPatientRepository implements PatientRepository {
  @override
  Future<PatientDetail> getPatient(String patientId) async {
    throw StateError('Patient not found: $patientId');
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
