import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/usecases/archive_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/check_duplicates.dart';
import 'package:ai_clinic/features/patients/domain/usecases/create_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/get_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/domain/usecases/reassign_patient_mrn.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/patients/domain/usecases/update_patient.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';

void main() {
  late FakePatientRepository repository;

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        patientRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
  }

  setUp(() {
    repository = FakePatientRepository(detail: samplePatientDetail());
  });

  test('searchPatientsUseCaseProvider wires SearchPatients to repository', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    final useCase = container.read(searchPatientsUseCaseProvider);
    expect(useCase, isA<SearchPatients>());

    await useCase(scope: PatientListScope.allBranches, query: 'wired');

    expect(repository.searchCallCount, 1);
    expect(repository.lastQuery, 'wired');
    expect(repository.lastScope, PatientListScope.allBranches);
  });

  test('getPatientUseCaseProvider wires GetPatient to repository', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    final useCase = container.read(getPatientUseCaseProvider);
    expect(useCase, isA<GetPatient>());

    await useCase('11111111-1111-4111-8111-111111111111');

    expect(repository.getPatientCallCount, 1);
  });

  test('checkDuplicatesUseCaseProvider wires CheckDuplicates to repository', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    final useCase = container.read(checkDuplicatesUseCaseProvider);
    expect(useCase, isA<CheckDuplicates>());

    await useCase(fullName: 'Dup Name', phone: '2017');

    expect(repository.duplicates, isEmpty);
  });

  test('createPatientUseCaseProvider wires CreatePatient to repository', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    final useCase = container.read(createPatientUseCaseProvider);
    expect(useCase, isA<CreatePatient>());

    const input = CreatePatientInput(
      activeBranchId: testBranchAId,
      fullName: 'Provider Patient',
      phone: '2017000001',
    );
    await useCase(input);

    expect(repository.createCallCount, 1);
    expect(repository.lastCreateInput, input);
  });

  test('updatePatientUseCaseProvider wires UpdatePatient to repository', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    final useCase = container.read(updatePatientUseCaseProvider);
    expect(useCase, isA<UpdatePatient>());

    final input = UpdatePatientInput(
      patientId: '11111111-1111-4111-8111-111111111111',
      fullName: 'Updated',
      expectedUpdatedAt: DateTime.utc(2026, 1, 1),
    );
    await useCase(input);

    expect(repository.lastUpdateInput, input);
  });

  test('archivePatientUseCaseProvider wires ArchivePatient to repository', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    final useCase = container.read(archivePatientUseCaseProvider);
    expect(useCase, isA<ArchivePatient>());

    await useCase('archive-me');

    expect(repository.archiveCallCount, 1);
    expect(repository.lastArchivedId, 'archive-me');
  });

  test('reassignPatientMrnUseCaseProvider wires ReassignPatientMrn to repository', () async {
    final container = createContainer();
    addTearDown(container.dispose);

    final useCase = container.read(reassignPatientMrnUseCaseProvider);
    expect(useCase, isA<ReassignPatientMrn>());

    final mrn = await useCase(patientId: 'patient-1', newMrn: 'MRN-000777');

    expect(mrn, 'MRN-000777');
  });
}
