import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart' as domain;
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/create_patient_modal.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/patient_test_support.dart';
import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';
import '../../support/patient_rpc_test_client.dart';
import 'create_patient_test_support.dart';

Future<void> _pumpEditModal(WidgetTester tester, Widget widget) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _pumpModal(WidgetTester tester, Widget widget) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _tapRegister(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('patient_register_submit')));
  await tester.tap(find.byKey(const Key('patient_register_submit')));
  await tester.pumpAndSettle();
}

Future<void> _selectGender(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(AppSelect<PatientGender>, 'Gender *'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _enterDateOfBirth(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(AppDateField, 'Date of birth *'), '15/01/1990');
  await tester.pumpAndSettle();
}

void main() {
  group('CreatePatientModal', () {
    testWidgets('shows form fields and register button over blurred backdrop', (tester) async {
      await _pumpModal(tester, _host());

      expect(find.text('Register patient'), findsWidgets);
      expect(find.text('Full name *'), findsOneWidget);
      expect(find.text('Mobile number *'), findsOneWidget);
      expect(find.text('Gender *'), findsOneWidget);
      expect(find.text('Marital status'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('empty name blocked on submit', (tester) async {
      await _pumpModal(tester, _host());

      await _tapRegister(tester);

      expect(find.text('Full name is required.'), findsOneWidget);
    });

    testWidgets('empty mobile blocked on submit', (tester) async {
      await _pumpModal(tester, _host());

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Patient');
      await _tapRegister(tester);

      expect(find.text('Mobile number is required.'), findsOneWidget);
    });

    testWidgets('M5: mobile field strips non-digit characters before validation', (tester) async {
      await _pumpModal(tester, _host());

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Patient');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), 'abc12');
      await _tapRegister(tester);

      expect(find.text('Only numbers are allowed.'), findsNothing);
      expect(find.text('Mobile number must be 8 to 15 digits.'), findsOneWidget);
    });

    testWidgets('empty gender blocked on submit', (tester) async {
      await _pumpModal(tester, _host());

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Patient');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '201005551234');
      await _tapRegister(tester);

      expect(find.text('Gender is required.'), findsOneWidget);
    });

    testWidgets('successful register closes modal with patient id', (tester) async {
      String? createdPatientId;

      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_host(onCreated: (id) => createdPatientId = id));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Patient');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '201005551234');
      await _enterDateOfBirth(tester);
      await _selectGender(tester, 'Male');
      await _tapRegister(tester);

      expect(createdPatientId, '33333333-3333-4333-8333-333333333333');
      expect(find.text('Patient registered successfully.'), findsOneWidget);
      expect(find.text('Register patient'), findsNothing);
    });

    testWidgets('DUPLICATE_WARNING shows dialog then retries with acknowledge', (tester) async {
      final client = _DuplicateThenSuccessClient();

      await _pumpModal(tester, _host(rpcClient: client));

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Dup Patient');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '201000000001');
      await _enterDateOfBirth(tester);
      await _selectGender(tester, 'Male');
      await _tapRegister(tester);

      expect(find.text('Similar patients found'), findsOneWidget);
      expect(find.text('Existing'), findsOneWidget);

      await tester.tap(find.text('Continue anyway'));
      await tester.pumpAndSettle();

      expect(client.createCallCount, 2);
      expect(client.lastParams?['p_acknowledge_duplicate'], true);
    });

    testWidgets('permission denied without patients.create', (tester) async {
      await _pumpModal(tester, _host(permissions: const {'patients.view'}));

      expect(find.text('You do not have permission to register patients.'), findsOneWidget);
      expect(find.byKey(const Key('patient_register_submit')), findsNothing);
    });

    testWidgets('close dismisses modal', (tester) async {
      await _pumpModal(tester, _host());

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Register patient'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('duplicate dialog Go back does not call RPC again', (tester) async {
      final client = _DuplicateThenSuccessClient();

      await _pumpModal(tester, _host(rpcClient: client));

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Dup Patient');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '201000000001');
      await _enterDateOfBirth(tester);
      await _selectGender(tester, 'Male');
      await _tapRegister(tester);

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();

      expect(client.createCallCount, 1);
    });

    testWidgets('L3: create trims leading and trailing whitespace from name and phone', (tester) async {
      final repository = FakePatientRepository();

      await _pumpModal(tester, _hostWithRepository(repository));

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), '  New Patient  ');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '  201005551234  ');
      await _enterDateOfBirth(tester);
      await _selectGender(tester, 'Male');
      await _tapRegister(tester);

      expect(repository.lastCreateInput?.fullName, 'New Patient');
      expect(repository.lastCreateInput?.phone, '201005551234');
    });
  });

  group('CreatePatientModal edit mode', () {
    testWidgets('prefills fields and shows Update button', (tester) async {
      final patient = samplePatientDetail(fullName: 'Existing Patient', phone: '201005551234', notes: 'Desk note');

      await _pumpEditModal(tester, _editHost(patient: patient));

      expect(find.text('Edit patient'), findsWidgets);
      expect(find.text('Update'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Full name *'), findsOneWidget);
      expect(find.text('Existing Patient'), findsOneWidget);
      expect(find.text('201005551234'), findsOneWidget);
      expect(find.text('Desk note'), findsOneWidget);
    });

    testWidgets('successful update closes modal', (tester) async {
      final patient = samplePatientDetail();
      final repository = FakePatientRepository(detail: patient);
      String? updatedPatientId;

      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _editHost(patient: patient, repository: repository, onUpdated: (id) => updatedPatientId = id),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Updated Patient');
      await tester.ensureVisible(find.byKey(const Key('patient_update_submit')));
      await tester.tap(find.byKey(const Key('patient_update_submit')));
      await tester.pumpAndSettle();

      expect(updatedPatientId, patient.id);
      expect(repository.lastUpdateInput?.fullName, 'Updated Patient');
      expect(find.text('Patient updated successfully.'), findsOneWidget);
      expect(find.text('Edit patient'), findsNothing);
    });

    testWidgets('permission denied without patients.edit', (tester) async {
      await _pumpEditModal(tester, _editHost(patient: samplePatientDetail(), permissions: const {'patients.view'}));

      expect(find.text('You do not have permission to edit patients.'), findsOneWidget);
      expect(find.byKey(const Key('patient_update_submit')), findsNothing);
    });

    testWidgets('L3: update trims leading and trailing whitespace from name and phone', (tester) async {
      final patient = samplePatientDetail();
      final repository = FakePatientRepository(detail: patient);

      await _pumpEditModal(tester, _editHost(patient: patient, repository: repository));

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), '  Updated Patient  ');
      await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '  201009991234  ');
      await tester.ensureVisible(find.byKey(const Key('patient_update_submit')));
      await tester.tap(find.byKey(const Key('patient_update_submit')));
      await tester.pumpAndSettle();

      expect(repository.lastUpdateInput?.fullName, 'Updated Patient');
      expect(repository.lastUpdateInput?.phone, '201009991234');
    });

    testWidgets('L5: successful update invalidates patient list provider', (tester) async {
      final patient = samplePatientDetail();
      final repository = FakePatientRepository(
        detail: patient,
        patients: [samplePatientListItem(id: patient.id, fullName: patient.fullName)],
      );

      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_editHostWithListWatch(patient: patient, repository: repository));
      await tester.pumpAndSettle();

      expect(repository.searchCallCount, 1);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Updated Patient');
      await tester.ensureVisible(find.byKey(const Key('patient_update_submit')));
      await tester.tap(find.byKey(const Key('patient_update_submit')));
      await tester.pumpAndSettle();

      expect(repository.searchCallCount, greaterThan(1));
    });
  });

  group('C. Create / Edit Patient — Functional (CP-F)', () {
    group('CP-F-003 — Create / No active branch', () {
      testWidgets('shows error when active branch is unset', (tester) async {
        await _pumpModal(
          tester,
          _host(
            authContext: sampleAuthSessionContext(
              permissions: const {'patients.view', 'patients.create'},
              branchIds: const [testBranchAId],
              activeBranchId: '',
            ),
          ),
        );

        await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Patient');
        await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '201005551234');
        await enterPatientDateOfBirth(tester);
        await selectPatientGender(tester, 'Male');
        await tapRegisterPatient(tester);

        expect(find.text('Select an active branch in the shell before registering a patient.'), findsOneWidget);
      });
    });

    group('CP-F-004 — Create / Required validation', () {
      testWidgets('shows field errors for name, phone, DOB, and gender on empty submit', (tester) async {
        await _pumpModal(tester, _host());

        await tapRegisterPatient(tester);

        expect(find.text('Full name is required.'), findsOneWidget);
        expect(find.text('Mobile number is required.'), findsOneWidget);
        expect(find.text('Date of birth is required.'), findsOneWidget);
        expect(find.text('Gender is required.'), findsOneWidget);
      });
    });

    group('CP-F-005 — Create / Phone digits only', () {
      testWidgets('blocks non-digit input and validates pasted mixed characters', (tester) async {
        await _pumpModal(tester, _host());

        await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Patient');
        await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), 'abc12def');
        await enterPatientDateOfBirth(tester);
        await selectPatientGender(tester, 'Male');
        await tapRegisterPatient(tester);

        expect(find.text('Only numbers are allowed.'), findsNothing);
        expect(find.text('Mobile number must be 8 to 15 digits.'), findsOneWidget);
      });
    });

    group('CP-F-006 — Create / Phone length 8–15', () {
      testWidgets('shows validation error for 7-digit phone', (tester) async {
        await _pumpModal(tester, _host());

        await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'New Patient');
        await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), '1234567');
        await enterPatientDateOfBirth(tester);
        await selectPatientGender(tester, 'Male');
        await tapRegisterPatient(tester);

        expect(find.text('Mobile number must be 8 to 15 digits.'), findsOneWidget);
      });
    });

    group('CP-F-008 — Create / Cancel', () {
      testWidgets('backdrop tap dismisses modal without creating', (tester) async {
        final repository = FakePatientRepository();

        await _pumpModal(tester, _hostWithRepository(repository));

        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        expect(find.text('Register patient'), findsNothing);
        expect(repository.createCallCount, 0);
      });
    });

    group('CP-F-009 — Create / Enter key submit', () {
      testWidgets('submits valid form when Enter is pressed', (tester) async {
        String? createdPatientId;

        await tester.binding.setSurfaceSize(const Size(900, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_host(onCreated: (id) => createdPatientId = id));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await fillValidCreatePatientForm(tester);
        await tester.tap(find.widgetWithText(AppTextField, 'Full name *'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(createdPatientId, '33333333-3333-4333-8333-333333333333');
        expect(find.text('Patient registered successfully.'), findsOneWidget);
      });
    });

    group('CP-F-010 — Create / Double submit guard', () {
      testWidgets('ignores second register tap while RPC is in flight', (tester) async {
        final repository = FakePatientRepository(createDelay: const Duration(milliseconds: 500));

        await _pumpModal(tester, _hostWithRepository(repository));

        await fillValidCreatePatientForm(tester);
        await tester.ensureVisible(find.byKey(const Key('patient_register_submit')));
        await tester.tap(find.byKey(const Key('patient_register_submit')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(repository.createCallCount, 1);

        await tester.pumpAndSettle();
        expect(repository.createCallCount, 1);
      });
    });

    group('CP-F-013 — Edit / Stale conflict', () {
      testWidgets('shows stale error and keeps modal open', (tester) async {
        final patient = samplePatientDetail();
        final repository = FakePatientRepository(
          detail: patient,
          updateException: RpcFailure(
            const RpcResult(success: false, errorCode: 'STALE_PATIENT', errorMessage: 'Stale'),
          ),
        );

        await _pumpEditModal(tester, _editHost(patient: patient, repository: repository));

        await tester.ensureVisible(find.byKey(const Key('patient_update_submit')));
        await tester.tap(find.byKey(const Key('patient_update_submit')));
        await tester.pumpAndSettle();

        expect(find.text('This record was updated elsewhere. Reload and try again.'), findsOneWidget);
        expect(find.text('Edit patient'), findsWidgets);
      });
    });

    group('CP-F-015 — Edit / Duplicate on update', () {
      testWidgets('shows duplicate dialog and retries with acknowledge on proceed', (tester) async {
        final patient = samplePatientDetail();
        final client = _DuplicateThenSuccessUpdateClient();

        await _pumpEditModal(tester, _editHost(patient: patient, rpcClient: client));

        await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Dup Update');
        await tapUpdatePatient(tester);

        expect(find.text('Similar patients found'), findsOneWidget);

        await tester.tap(find.text('Continue anyway'));
        await tester.pumpAndSettle();

        expect(client.updateCallCount, 2);
        expect(client.lastParams?['p_acknowledge_duplicate'], true);
        expect(find.text('Patient updated successfully.'), findsOneWidget);
      });
    });

    group('INT-005 — Offline during create', () {
      testWidgets('shows error and keeps modal open when create RPC fails', (tester) async {
        final repository = FakePatientRepository(createException: StateError('Network failure'));

        await _pumpModal(tester, _hostWithRepository(repository));

        await fillValidCreatePatientForm(tester);
        await tapRegisterPatient(tester);

        expect(find.textContaining('Network failure'), findsOneWidget);
        expect(find.text('Register patient'), findsWidgets);
        expect(repository.createCallCount, 1);
      });
    });

    group('INT-006 — Multi-tab same patient edit', () {
      testWidgets('second edit with stale expectedUpdatedAt shows conflict message', (tester) async {
        final patient = samplePatientDetail(updatedAt: DateTime.utc(2026, 1, 1));
        final repository = _StaleOnSecondUpdateRepository(patient);

        await _pumpEditModal(tester, _editHost(patient: patient, repository: repository));
        await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'First Edit');
        await tapUpdatePatient(tester);
        expect(find.text('Patient updated successfully.'), findsOneWidget);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await _pumpEditModal(tester, _editHost(patient: patient, repository: repository));
        await tapUpdatePatient(tester);

        expect(find.text('This record was updated elsewhere. Reload and try again.'), findsOneWidget);
      });
    });

    group('AB-004 — Modal backdrop spam', () {
      testWidgets('repeated backdrop taps dismiss once without creating', (tester) async {
        final repository = FakePatientRepository();

        await _pumpModal(tester, _hostWithRepository(repository));

        for (var i = 0; i < 5; i++) {
          await tester.tapAt(const Offset(20, 20));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.pumpAndSettle();

        expect(find.text('Register patient'), findsNothing);
        expect(repository.createCallCount, 0);
        expect(tester.takeException(), isNull);
      });
    });

    group('UI-007 — Modal fade', () {
      testWidgets('FadeTransition present when opening create modal', (tester) async {
        await _pumpModal(tester, _host());

        expect(find.byType(FadeTransition), findsWidgets);

        await tester.pump(const Duration(milliseconds: 100));
        final fade = tester.widget<FadeTransition>(find.byType(FadeTransition).first);
        expect(fade.opacity.value, greaterThan(0));
      });
    });
  });
}

class _DuplicateThenSuccessClient extends PatientRpcTestClient {
  int createCallCount = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'create_patient') {
      createCallCount++;
      if (createCallCount == 1) {
        lastFunction = fn;
        lastParams = params == null ? null : Map<String, dynamic>.from(params);
        return FakePostgrestRpc({
              'success': false,
              'error_code': 'DUPLICATE_WARNING',
              'error_message': 'Similar patients found',
              'data': {
                'candidates': [
                  {'id': '22222222-2222-4222-8222-222222222222', 'full_name': 'Existing', 'branch_name': 'Main'},
                ],
              },
            })
            as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _DuplicateThenSuccessUpdateClient extends PatientRpcTestClient {
  int updateCallCount = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'update_patient') {
      updateCallCount++;
      if (updateCallCount == 1) {
        lastFunction = fn;
        lastParams = params == null ? null : Map<String, dynamic>.from(params);
        return FakePostgrestRpc({
              'success': false,
              'error_code': 'DUPLICATE_WARNING',
              'error_message': 'Similar patients found',
              'data': {
                'candidates': [
                  {'id': '22222222-2222-4222-8222-222222222222', 'full_name': 'Existing', 'branch_name': 'Main'},
                ],
              },
            })
            as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc(fn, params: params, get: get);
  }
}

Widget _editHost({
  required PatientDetail patient,
  FakePatientRepository? repository,
  PatientRpcTestClient? rpcClient,
  Set<String> permissions = const {'patients.view', 'patients.edit'},
  void Function(String patientId)? onUpdated,
}) {
  final domain.PatientRepository repo;
  if (repository != null) {
    repo = repository;
  } else if (rpcClient != null) {
    repo = PatientRepositoryImpl(rpcClient);
  } else {
    repo = FakePatientRepository(detail: patient);
  }

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(permissions: permissions),
          ),
        ),
      ),
      patientRepositoryProvider.overrideWith((ref) => repo),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: AppButton(
                label: 'Open',
                onPressed: () async {
                  final patientId = await CreatePatientModal.showEdit(context, patient: patient);
                  if (patientId != null) {
                    onUpdated?.call(patientId);
                  }
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}

Widget _editHostWithListWatch({required PatientDetail patient, required FakePatientRepository repository}) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(permissions: const {'patients.view', 'patients.edit'}),
          ),
        ),
      ),
      patientRepositoryProvider.overrideWith((ref) => repository),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      home: Consumer(
        builder: (context, ref, _) {
          ref.watch(patientListProvider);
          return Scaffold(
            body: Center(
              child: AppButton(
                label: 'Open',
                onPressed: () async {
                  await CreatePatientModal.showEdit(context, patient: patient);
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}

Widget _hostWithRepository(FakePatientRepository repository) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(permissions: const {'patients.view', 'patients.create'}),
          ),
        ),
      ),
      patientRepositoryProvider.overrideWith((ref) => repository),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: AppButton(label: 'Open', onPressed: () => CreatePatientModal.show(context)),
            ),
          );
        },
      ),
    ),
  );
}

Widget _host({
  PatientRpcTestClient? rpcClient,
  Set<String> permissions = const {'patients.view', 'patients.create'},
  AuthSessionContext? authContext,
  void Function(String patientId)? onCreated,
}) {
  final client = rpcClient ?? PatientRpcTestClient();

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: authContext ?? sampleAuthSessionContext(permissions: permissions),
          ),
        ),
      ),
      patientRepositoryProvider.overrideWith((ref) => PatientRepositoryImpl(client)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: AppButton(
                label: 'Open',
                onPressed: () async {
                  final patientId = await CreatePatientModal.show(context);
                  if (patientId != null) {
                    onCreated?.call(patientId);
                  }
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _StaleOnSecondUpdateRepository extends FakePatientRepository {
  _StaleOnSecondUpdateRepository(PatientDetail detail) : super(detail: detail);

  var _updateCount = 0;

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) async {
    _updateCount++;
    if (_updateCount > 1) {
      throw RpcFailure(const RpcResult(success: false, errorCode: 'STALE_PATIENT', errorMessage: 'Stale'));
    }
    return super.updatePatient(input);
  }
}
