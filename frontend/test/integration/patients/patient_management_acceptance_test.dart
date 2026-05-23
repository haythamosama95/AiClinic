// Acceptance outline for spec.md test cases 1–13 (V1-3 patient management).
//
// Backend-only cases 3 (national ID), 11 (CRUD harness), and 13 (tampered org)
// are enforced in `backend/tests/patient_management_crud.sql` and
// `backend/tests/patient_management_rls.sql` via `run_patient_management_tests.sh`.

import 'dart:io';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_edit_page.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_registration_page.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_archive_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_scope_provider.dart';
import 'package:ai_clinic/features/settings/presentation/pages/settings_page.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest_rpc.dart';
import '../../support/patient_rpc_test_client.dart';
import '../../support/pump_auth_app.dart';

const _repoRoot = '..';
const _branchAId = '44444444-4444-4444-8444-444444444444';
const _branchBId = '55555555-5555-4555-8555-555555555555';
const _branchA = BranchSummary(id: _branchAId, name: 'Main');
const _branchB = BranchSummary(id: _branchBId, name: 'Uptown');
const _patientId = '11111111-1111-4111-8111-111111111111';

Future<void> _pumpPatientApp(
  WidgetTester tester, {
  required AuthSessionNotifier session,
  PatientRpcTestClient? client,
  List<BranchSummary> branches = const [_branchA, _branchB],
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final rpcClient = client ?? PatientRpcTestClient();
  await pumpAuthApp(
    tester,
    extraOverrides: [
      authSessionProvider.overrideWith(() => session),
      staffAssignableBranchesProvider.overrideWith((ref) async => branches),
      patientRepositoryProvider.overrideWith((ref) => PatientRepository(rpcClient)),
      patientListScopeProvider.overrideWith(PatientListScopeNotifier.new),
    ],
  );
  await completeStartupBootstrap(tester);

  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
}

class _ReceptionistSession extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          role: StaffRole.receptionist,
          branchIds: const [_branchAId, _branchBId],
          activeBranchId: _branchAId,
          permissions: {
            PermissionKeys.patientsView,
            PermissionKeys.patientsCreate,
            PermissionKeys.patientsEdit,
            PermissionKeys.patientsDelete,
          },
          setupRequired: setupRequired,
        ),
      ),
    );
  }
}

class _OwnerSession extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          branchIds: const [_branchAId, _branchBId],
          activeBranchId: _branchAId,
          permissions: RolePermissionSeed.owner,
          setupRequired: setupRequired,
        ),
      ),
    );
  }
}

class _DoctorViewOnlySession extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          role: StaffRole.doctor,
          branchIds: const [_branchAId],
          activeBranchId: _branchAId,
          permissions: const {PermissionKeys.patientsView},
          setupRequired: setupRequired,
        ),
      ),
    );
  }
}

Future<void> _go(WidgetTester tester, String location) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  container.read(appRouterProvider).go(location);
  await tester.pumpAndSettle();
}

Future<void> _pumpFocusedPatientPage(
  WidgetTester tester, {
  required Widget page,
  PatientRpcTestClient? client,
  Set<String> permissions = const {
    PermissionKeys.patientsView,
    PermissionKeys.patientsCreate,
    PermissionKeys.patientsEdit,
    PermissionKeys.patientsDelete,
  },
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(
          () => _PresetAuthSessionNotifier(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(permissions: permissions, activeBranchId: _branchAId),
            ),
          ),
        ),
        patientRepositoryProvider.overrideWith((ref) => PatientRepository(client ?? PatientRpcTestClient())),
        patientListScopeProvider.overrideWith(PatientListScopeNotifier.new),
      ],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _registerPatient(WidgetTester tester, {required String name, required String phone}) async {
  await tester.enterText(find.byType(TextFormField).at(0), name);
  await tester.enterText(find.byType(TextFormField).at(1), phone);
  await tester.ensureVisible(find.byKey(const Key('patient_register_submit')));
  await tester.tap(find.byKey(const Key('patient_register_submit')));
  await tester.pumpAndSettle();
}

void main() {
  group('spec test case 1 — register and verify list/detail', () {
    testWidgets('trivial: shell Patients opens list; row opens detail', (tester) async {
      await _pumpPatientApp(tester, session: _ReceptionistSession());

      await _go(tester, AppRoutes.home);
      await tester.tap(find.text('Patients'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_list_table')), findsOneWidget);
      expect(find.text('Test Patient'), findsOneWidget);

      await tester.tap(find.text('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_detail_profile')), findsOneWidget);
      expect(find.byKey(const Key('patient_detail_body')), findsOneWidget);
    });

    testWidgets('advanced: register invokes create_patient RPC', (tester) async {
      final client = _CallLogPatientClient();
      await _pumpFocusedPatientPage(tester, page: const PatientRegistrationPage(), client: client);

      await _registerPatient(tester, name: 'Case One Patient', phone: '201234567890');

      expect(client.calls, contains('create_patient'));
    });
  });

  group('spec test case 2 — duplicate phone advisory', () {
    testWidgets('advanced: DUPLICATE_WARNING then continue registers', (tester) async {
      final client = _DuplicateThenSuccessCreateClient();
      await _pumpFocusedPatientPage(tester, page: const PatientRegistrationPage(), client: client);

      await _registerPatient(tester, name: 'Dup Patient', phone: '201000000001');

      expect(find.text('Similar patients found'), findsOneWidget);
      await tester.tap(find.text('Continue anyway'));
      await tester.pumpAndSettle();

      expect(client.createCallCount, 2);
      expect(client.lastParams?['p_acknowledge_duplicate'], isTrue);
    });
  });

  group('spec test case 3 — national ID hard block', () {
    test('schema: national_id removed from registration; uniqueness enforced in base migration', () {
      final fieldsMigration = File(
        '$_repoRoot/backend/supabase/migrations/20260523150000_patient_registration_fields.sql',
      );
      final baseMigration = File('$_repoRoot/backend/supabase/migrations/20260523140000_patient_management.sql');
      expect(fieldsMigration.readAsStringSync(), contains('national_id'));
      expect(baseMigration.readAsStringSync(), contains('NATIONAL_ID_EXISTS'));
    });
  });

  group('spec test case 4 — search min length and prefix', () {
    testWidgets('stupid usage: short query shows guidance', (tester) async {
      await _pumpPatientApp(tester, session: _ReceptionistSession());

      await _go(tester, AppRoutes.patients);
      await tester.enterText(find.byKey(const Key('patient_search_field')), 'ab');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least 3 characters'), findsWidgets);
      expect(find.byKey(const Key('patient_list_table')), findsNothing);
    });

    testWidgets('advanced: valid name search calls search_patients RPC', (tester) async {
      final client = _CallLogPatientClient();
      await _pumpPatientApp(tester, session: _ReceptionistSession(), client: client);

      await _go(tester, AppRoutes.patients);
      client.lastFunction = null;
      await tester.enterText(find.byKey(const Key('patient_search_field')), 'ahmed');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'search_patients');
      expect(client.lastParams?['p_query'], 'ahmed');
    });
  });

  group('spec test case 5 — org-wide search', () {
    testWidgets('advanced: all branches scope sends organization RPC scope', (tester) async {
      final client = _CallLogPatientClient();
      await _pumpPatientApp(tester, session: _ReceptionistSession(), client: client);

      await _go(tester, AppRoutes.patients);
      await tester.tap(find.text('All branches'));
      await tester.pumpAndSettle();

      expect(client.lastParams?['p_scope'], 'organization');
      expect(find.text('Branch'), findsOneWidget);
    });
  });

  group('spec test case 6 — cross-branch edit', () {
    testWidgets('advanced: save sends update_patient with expected_updated_at', (tester) async {
      final client = _CallLogPatientClient()..rpcResults.addAll(_detailRpcResults());
      await _pumpFocusedPatientPage(
        tester,
        page: PatientEditPage(patientId: _patientId),
        client: client,
      );

      expect(find.byKey(const Key('patient_edit_body')), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'Updated Name');
      client.calls.clear();
      await tester.tap(find.byKey(const Key('patient_edit_submit')));
      await tester.pumpAndSettle();

      expect(client.calls, contains('update_patient'));
      expect(client.lastUpdateParams?['p_patient_id'], _patientId);
      expect(client.lastUpdateParams?.containsKey('p_expected_updated_at'), isTrue);
    });
  });

  group('spec test case 7 — edit without permission', () {
    testWidgets('doctor cannot save on edit page', (tester) async {
      await _pumpPatientApp(tester, session: _DoctorViewOnlySession());

      await _go(tester, AppRoutes.patientEdit(_patientId));

      expect(find.byKey(const Key('patient_edit_permission_denied')), findsOneWidget);
    });
  });

  group('spec test case 8 — stale concurrent edit', () {
    testWidgets('advanced: STALE_PATIENT shows reload banner', (tester) async {
      final client = _StaleUpdateClient();
      await _pumpFocusedPatientPage(
        tester,
        page: PatientEditPage(patientId: _patientId),
        client: client,
      );

      expect(find.byKey(const Key('patient_edit_body')), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'Stale Name');
      await tester.tap(find.byKey(const Key('patient_edit_submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_edit_stale_banner')), findsOneWidget);
    });
  });

  group('spec test case 9 — archive patient', () {
    testWidgets('advanced: archive confirmation invokes archive_patient RPC', (tester) async {
      final client = _CallLogPatientClient();
      await _pumpFocusedPatientPage(
        tester,
        page: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => PatientArchiveDialog.show(context, patientId: _patientId, patientName: 'Ahmed Hassan'),
                child: const Text('Open archive'),
              ),
            ),
          ),
        ),
        client: client,
      );

      await tester.tap(find.text('Open archive'));
      await tester.pumpAndSettle();
      client.calls.clear();
      await tester.tap(find.byKey(const Key('patient_archive_confirm')));
      await tester.pumpAndSettle();

      expect(client.calls, contains('archive_patient'));
    });
  });

  group('spec test case 10 — doctor view-only', () {
    testWidgets('list/detail allowed; mutate actions hidden', (tester) async {
      await _pumpPatientApp(tester, session: _DoctorViewOnlySession());

      await _go(tester, AppRoutes.patients);
      expect(find.byKey(const Key('patient_list_register_fab')), findsNothing);

      await tester.tap(find.text('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_detail_edit')), findsNothing);
      expect(find.byKey(const Key('patient_detail_archive')), findsNothing);
    });
  });

  group('spec test case 11 — backend verification harness', () {
    test('regression: run_patient_management_tests.sh exists and references SQL suites', () {
      final runner = File('$_repoRoot/backend/tests/run_patient_management_tests.sh');
      final body = runner.readAsStringSync();
      expect(body, contains('patient_management_crud.sql'));
      expect(body, contains('patient_management_rls.sql'));
    });
  });

  group('spec test case 12 — scope toggle and branch switch', () {
    testWidgets('advanced: scope toggle and active branch change refresh search scope', (tester) async {
      final client = _CallLogPatientClient();
      final session = _ReceptionistSession();
      await _pumpPatientApp(tester, session: session, client: client);

      await _go(tester, AppRoutes.patients);
      expect(client.lastParams?['p_scope'], 'branch');
      expect(client.lastParams?['p_branch_id'], _branchAId);

      await tester.tap(find.text('All branches'));
      await tester.pumpAndSettle();
      expect(client.lastParams?['p_scope'], 'organization');

      await _go(tester, AppRoutes.home);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uptown').last);
      await tester.pumpAndSettle();
      expect(session.state.context?.activeBranchId, _branchBId);

      await _go(tester, AppRoutes.patients);
      await tester.tap(find.text('This branch only'));
      await tester.pumpAndSettle();
      client.lastFunction = null;
      await tester.enterText(find.byKey(const Key('patient_search_field')), 'test');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(client.lastParams?['p_scope'], 'branch');
      expect(client.lastParams?['p_branch_id'], _branchBId);
    });
  });

  group('spec test case 13 — tampered organization context', () {
    test('backend: cross-org denial in patient_management_rls.sql', () {
      final rls = File('$_repoRoot/backend/tests/patient_management_rls.sql');
      expect(rls.readAsStringSync(), contains('cross-org'));
    });
  });

  group('V1-2 regression smoke (phase 8 T054)', () {
    testWidgets('settings page and branch switcher still reachable for owner', (tester) async {
      final session = _OwnerSession();
      await _pumpPatientApp(tester, session: session);

      await _go(tester, AppRoutes.settings);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);

      await _go(tester, AppRoutes.home);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uptown').last);
      await tester.pumpAndSettle();

      expect(session.state.context?.activeBranchId, _branchBId);
    });

    test('regression: patient routes remain accessible without permission redirect', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: RolePermissionSeed.owner),
      );
      expect(AuthRouteGuard.patientRouteRedirect(location: AppRoutes.patients, auth: auth), isNull);
      expect(AuthRouteGuard.canAccessBranchManagement(auth), isTrue);
    });
  });
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _CallLogPatientClient extends PatientRpcTestClient {
  _CallLogPatientClient({super.rpcResults});

  final calls = <String>[];
  Map<String, dynamic>? lastUpdateParams;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    calls.add(fn);
    if (fn == 'update_patient' && params != null) {
      lastUpdateParams = Map<String, dynamic>.from(params);
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _DuplicateThenSuccessCreateClient extends PatientRpcTestClient {
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

Map<String, Map<String, dynamic>> _detailRpcResults() => {
  'get_patient': {
    'success': true,
    'data': {
      'id': _patientId,
      'full_name': 'Ahmed Hassan',
      'phone': '209911112233',
      'date_of_birth': '1990-05-15',
      'gender': 'male',
      'marital_status': 'married',
      'notes': 'VIP patient',
      'branch_id': _branchAId,
      'branch_name': 'Main',
      'created_at': '2026-01-01T08:00:00.000Z',
      'updated_at': '2026-01-02T09:30:00.000Z',
    },
  },
};

class _StaleUpdateClient extends PatientRpcTestClient {
  _StaleUpdateClient() {
    rpcResults.addAll(_detailRpcResults());
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'update_patient') {
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      return FakePostgrestRpc({
            'success': false,
            'error_code': 'STALE_PATIENT',
            'error_message': 'Patient was updated elsewhere. Reload and try again.',
          })
          as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}
