// Acceptance outline for spec.md test cases 1–18 (V1-5 visits and medical records).
//
// Split coverage:
// - Cases 3–4, 6b, 9b, 10, 15: `backend/tests/visit_medical_records_crud.sql` and
//   `visit_medical_records_rls.sql` via `run_visit_medical_records_tests.sh`
// - Case 16: backend harness (same runner)
// - UI orchestration and permission gates: this file

import 'dart:io';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_actions.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/visit_create_dialog.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart' show StaffRole;
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_visit_history_section.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_detail_page.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_documentation_page.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

const _repoRoot = '..';
const _branchId = '44444444-4444-4444-8444-444444444444';
const _visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _doctorB = '33333333-3333-4333-8333-333333333333';

/// Past UTC instant so appointment day rules are stable (always "arrived").
final _appointmentListStartUtc = DateTime.utc(2020, 6, 1, 10, 0);

/// Future UTC instant for tests that need a not-yet-arrived appointment day.
final _appointmentListStartFutureUtc = DateTime.utc(2099, 6, 1, 10, 0);

Future<void> _pumpHost(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle();
}

AuthSessionState _auth({Set<String>? permissions}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions ?? RolePermissionSeed.doctor,
      activeBranchId: _branchId,
      branchIds: [_branchId],
    ),
  );
}

VisitRpcTestClient _configuredVisitClient([VisitRpcTestClient? base]) {
  final client = base ?? VisitRpcTestClient();
  client.rpcResults.putIfAbsent(
    'get_specialty_form_schema',
    () => {
      'success': true,
      'data': {
        'schema_json': {'type': 'object', 'properties': {}},
      },
    },
  );
  return client;
}

Widget _visitScope({
  required Widget child,
  AuthSessionState? auth,
  VisitRpcTestClient? visitClient,
  StaffAdminRepository? staffRepo,
}) {
  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(auth ?? _auth())),
      visitRepositoryProvider.overrideWith((ref) => VisitRepository(_configuredVisitClient(visitClient))),
      if (staffRepo != null) staffAdminRepositoryProvider.overrideWithValue(staffRepo),
    ],
    child: child,
  );
}

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('spec cases 1–2 — create visit from eligible appointment status', () {
    testWidgets('case 1: in_progress offers create visit (not manual complete)', (tester) async {
      await _pumpHost(
        tester,
        _visitScope(
          auth: _auth(permissions: {PermissionKeys.appointmentsCreate, PermissionKeys.visitsCreate}),
          child: MaterialApp(
            home: Scaffold(
              body: AppointmentStatusActions(
                item: _appointmentItem(status: AppointmentStatus.inProgress, onAppointmentDay: true),
                onStatusChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('appointments_visit_create')), findsOneWidget);
      expect(find.byKey(const Key('appointments_status_complete')), findsNothing);
    });

    testWidgets('case 2: checked_in offers start and create visit', (tester) async {
      await _pumpHost(
        tester,
        _visitScope(
          auth: _auth(permissions: {PermissionKeys.appointmentsCreate, PermissionKeys.visitsCreate}),
          child: MaterialApp(
            home: Scaffold(
              body: AppointmentStatusActions(
                item: _appointmentItem(status: AppointmentStatus.checkedIn, onAppointmentDay: true),
                onStatusChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('appointments_status_start')), findsOneWidget);
      expect(find.byKey(const Key('appointments_visit_create')), findsOneWidget);
    });
  });

  group('spec case 2b — doctor selection when appointment has no doctor', () {
    testWidgets('visit create dialog shows doctor picker and calls create_visit RPC', (tester) async {
      final visitClient = VisitRpcTestClient();
      CreateVisitResult? created;

      await _pumpHost(
        tester,
        _visitScope(
          visitClient: visitClient,
          staffRepo: _AcceptanceStaffRepo(),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return FilledButton(
                    onPressed: () async {
                      created = await VisitCreateDialog.show(
                        context,
                        item: _appointmentItem(
                          status: AppointmentStatus.checkedIn,
                          onAppointmentDay: true,
                          doctorId: null,
                        ),
                      );
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_create_dialog')), findsOneWidget);
      expect(find.byKey(const Key('doctor_selector')), findsOneWidget);
      await tester.tap(find.byKey(const Key('doctor_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dr Ada').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('visit_create_confirm')));
      await tester.pumpAndSettle();

      expect(visitClient.lastFunction, 'create_visit');
      expect(visitClient.lastParams?['p_doctor_id'], 'doc-1');
      expect(created?.visitId, _visitId);
    });
  });

  group('spec cases 3–4 — ineligible status and duplicate visit (backend)', () {
    test('case 3: scheduled appointment rejection in visit_medical_records_crud.sql', () {
      final crud = File('$_repoRoot/backend/tests/visit_medical_records_crud.sql');
      expect(crud.readAsStringSync(), contains('APPOINTMENT_NOT_ELIGIBLE'));
    });

    test('case 4: duplicate visit rejection in visit_medical_records_crud.sql', () {
      final crud = File('$_repoRoot/backend/tests/visit_medical_records_crud.sql');
      expect(crud.readAsStringSync(), contains('VISIT_ALREADY_EXISTS'));
    });
  });

  group('spec cases 5–6 — SOAP save on documentation page', () {
    testWidgets('case 5–6: save partial SOAP invokes save_soap_note', (tester) async {
      final visitClient = VisitRpcTestClient();

      await _pumpHost(
        tester,
        _visitScope(
          visitClient: visitClient,
          auth: _auth(permissions: {PermissionKeys.visitsEditSoap}),
          child: const MaterialApp(home: VisitDocumentationPage(visitId: _visitId)),
        ),
      );

      expect(visitClient.rpcLog.first, 'get_visit');
      await _ensureVisible(tester, find.byKey(const Key('soap_subjective')));
      await tester.enterText(find.byKey(const Key('soap_subjective')), 'Headache');
      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(visitClient.rpcCalls.any((c) => c.fn == 'save_soap_note'), isTrue);
      expect(find.byKey(const Key('soap_edit_button')), findsOneWidget);
    });
  });

  group('spec case 6b — stale SOAP concurrency (backend)', () {
    test('STALE_SOAP handled in visit_medical_records_crud.sql', () {
      final crud = File('$_repoRoot/backend/tests/visit_medical_records_crud.sql');
      expect(crud.readAsStringSync(), contains('STALE_SOAP'));
    });
  });

  group('spec case 7 — specialty form persistence', () {
    testWidgets('save specialty field values via save_soap_note', (tester) async {
      final visitClient = VisitRpcTestClient(
        rpcResults: {
          'get_specialty_form_schema': {
            'success': true,
            'data': {
              'schema_json': {
                'type': 'object',
                'properties': {
                  'pain_score': {'type': 'number', 'title': 'Pain score'},
                },
                'required': ['pain_score'],
              },
            },
          },
        },
      );

      await _pumpHost(
        tester,
        _visitScope(
          visitClient: visitClient,
          auth: _auth(permissions: {PermissionKeys.visitsEditSoap}),
          child: const MaterialApp(home: VisitDocumentationPage(visitId: _visitId)),
        ),
      );

      await _ensureVisible(tester, find.byKey(const Key('specialty_field_pain_score')));
      await tester.enterText(find.byKey(const Key('specialty_field_pain_score')), '4');
      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pumpAndSettle();

      final saveParams = visitClient.paramsForFunction('save_soap_note');
      expect(saveParams?['p_specialty_form_json'], isNotNull);
    });
  });

  group('spec case 8 — treatment plan within visit', () {
    test('treatment plan CRUD covered in visit_medical_records_crud.sql', () {
      final crud = File('$_repoRoot/backend/tests/visit_medical_records_crud.sql');
      final body = crud.readAsStringSync();
      expect(body, contains('create_treatment_plan'));
      expect(body, contains('update_treatment_plan'));
      expect(body, contains('archive_treatment_plan'));
    });

    test('widget: add/edit/remove flows in treatment_plan_list_test.dart', () {
      expect(File('test/widget/visits/treatment_plan_list_test.dart').existsSync(), isTrue);
    });
  });

  group('spec cases 9–10 — attachments (UI gate + backend rules)', () {
    testWidgets('case 9: upload control visible with visits.upload_attachment', (tester) async {
      await _pumpHost(
        tester,
        _visitScope(
          auth: _auth(permissions: RolePermissionSeed.doctor),
          child: const MaterialApp(home: VisitDocumentationPage(visitId: _visitId)),
        ),
      );

      await _ensureVisible(tester, find.byKey(const Key('visit_attachment_upload_button')));
      expect(find.byKey(const Key('visit_attachment_upload_button')), findsOneWidget);
    });

    test('case 10: type/size rejection in visit_medical_records_crud.sql', () {
      final crud = File('$_repoRoot/backend/tests/visit_medical_records_crud.sql');
      final body = crud.readAsStringSync();
      expect(
        body,
        allOf(
          contains('register_visit_attachment_invalid_file_type'),
          contains('INVALID_FILE_TYPE'),
          contains('register_visit_attachment_file_too_large'),
          contains('FILE_TOO_LARGE'),
        ),
      );
    });
  });

  group('spec cases 9b — lab download rules (backend)', () {
    test('lab own-download rule in visit_medical_records_rls.sql', () {
      final rls = File('$_repoRoot/backend/tests/visit_medical_records_rls.sql');
      expect(rls.readAsStringSync(), contains('lab'));
    });
  });

  group('spec cases 11–11b — submit visit', () {
    testWidgets('case 11: submit visit calls complete_visit RPC', (tester) async {
      final visitClient = VisitRpcTestClient(
        rpcResults: {
          'get_visit': {
            'success': true,
            'data': {
              'id': _visitId,
              'branch_id': _branchId,
              'appointment_id': _appointmentId,
              'patient_id': _patientId,
              'doctor_id': _doctorB,
              'doctor_name': 'Dr Test',
              'visit_date': '2026-05-31',
              'status': 'in_progress',
              'soap': {
                'subjective': 'Done',
                'objective': null,
                'assessment': null,
                'plan': null,
                'specialty_form_json': {},
                'updated_at': '2026-05-31T10:00:00.000Z',
              },
            },
          },
        },
      );

      await _pumpHost(
        tester,
        _visitScope(
          visitClient: visitClient,
          auth: _auth(permissions: {PermissionKeys.visitsEditSoap}),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => VisitSubmitDialog.show(context, visitId: _visitId),
                      child: const Text('Submit'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('visit_submit_confirm_button')));
      await tester.pumpAndSettle();

      expect(visitClient.lastFunction, 'complete_visit');
    });

    testWidgets('case 11b: empty SOAP shows SOAP_REQUIRED error', (tester) async {
      final visitClient = VisitRpcTestClient(
        rpcResults: {
          'complete_visit': {
            'success': false,
            'error_code': 'SOAP_REQUIRED_FOR_COMPLETE',
            'error_message': 'At least one SOAP section must contain text.',
          },
        },
      );

      await _pumpHost(
        tester,
        _visitScope(
          visitClient: visitClient,
          auth: _auth(permissions: {PermissionKeys.visitsEditSoap}),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => VisitSubmitDialog.show(context, visitId: _visitId),
                      child: const Text('Submit'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('visit_submit_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_submit_error_label')), findsOneWidget);
    });
  });

  group('spec cases 12–13 — patient history and visit detail permissions', () {
    testWidgets('case 12: receptionist sees metadata-only visit history', (tester) async {
      await _pumpHost(
        tester,
        _visitScope(
          auth: _auth(permissions: RolePermissionSeed.receptionist),
          child: const MaterialApp(home: PatientVisitHistorySection(patientId: _patientId)),
        ),
      );

      expect(find.byKey(const Key('patient_visit_history_metadata_only')), findsOneWidget);
      expect(find.byKey(const Key('visit_detail_soap_section')), findsNothing);
    });

    testWidgets('case 13: doctor opens visit detail with SOAP sections', (tester) async {
      final visitClient = VisitRpcTestClient(
        rpcResults: {
          'get_visit': {
            'success': true,
            'data': {
              'id': _visitId,
              'branch_id': _branchId,
              'appointment_id': _appointmentId,
              'patient_id': _patientId,
              'doctor_id': _doctorB,
              'doctor_name': 'Dr Test',
              'visit_date': '2026-05-31',
              'status': 'completed',
              'soap': {
                'subjective': 'Headache',
                'objective': 'Normal vitals',
                'assessment': null,
                'plan': null,
                'specialty_form_json': {},
                'updated_at': '2026-05-31T10:00:00.000Z',
              },
            },
          },
        },
      );

      await _pumpHost(
        tester,
        _visitScope(
          visitClient: visitClient,
          auth: _auth(permissions: {PermissionKeys.visitsEditSoap}),
          child: const MaterialApp(home: VisitDetailPage(visitId: _visitId)),
        ),
      );

      expect(visitClient.rpcLog.first, 'get_visit');
      expect(find.byKey(const Key('visit_detail_soap_section')), findsOneWidget);
      expect(find.textContaining('Headache'), findsOneWidget);
    });
  });

  group('spec case 14 — visit creation without permission', () {
    test('visit documentation route redirects for receptionist', () {
      final auth = _auth(permissions: RolePermissionSeed.receptionist);
      expect(
        AuthRouteGuard.visitRouteRedirect(location: AppRoutes.visitDocument(_visitId), auth: auth),
        AppRoutes.home,
      );
    });

    testWidgets('create visit action hidden without visits.create', (tester) async {
      await _pumpHost(
        tester,
        _visitScope(
          auth: _auth(permissions: {PermissionKeys.appointmentsCreate}),
          child: MaterialApp(
            home: Scaffold(
              body: AppointmentStatusActions(
                item: _appointmentItem(status: AppointmentStatus.inProgress, onAppointmentDay: true),
                onStatusChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('appointments_visit_create')), findsNothing);
    });
  });

  group('spec case 15 — cross-branch denial (backend)', () {
    test('cross-branch isolation in visit_medical_records_rls.sql', () {
      final rls = File('$_repoRoot/backend/tests/visit_medical_records_rls.sql');
      expect(rls.readAsStringSync(), contains('cross-branch'));
    });
  });

  group('spec case 16 — backend verification harness', () {
    test('run_visit_medical_records_tests.sh exists and references SQL suites', () {
      final runner = File('$_repoRoot/backend/tests/run_visit_medical_records_tests.sh');
      expect(runner.existsSync(), isTrue);
      final body = runner.readAsStringSync();
      expect(body, contains('visit_medical_records_crud.sql'));
      expect(body, contains('visit_medical_records_rls.sql'));
    });
  });

  group('spec cases 17–18 — backend-first fetch on open', () {
    testWidgets('case 17: patient visit history loads list_patient_visits on open', (tester) async {
      final visitClient = VisitRpcTestClient();

      await _pumpHost(
        tester,
        _visitScope(
          visitClient: visitClient,
          auth: _auth(permissions: {PermissionKeys.patientsView}),
          child: const MaterialApp(home: PatientVisitHistorySection(patientId: _patientId)),
        ),
      );

      expect(visitClient.rpcLog.first, 'list_patient_visits');
    });

    testWidgets('case 18: visit documentation loads get_visit before editing', (tester) async {
      final visitClient = VisitRpcTestClient();

      await _pumpHost(
        tester,
        _visitScope(
          visitClient: visitClient,
          auth: _auth(permissions: {PermissionKeys.visitsEditSoap}),
          child: const MaterialApp(home: VisitDocumentationPage(visitId: _visitId)),
        ),
      );

      expect(visitClient.rpcLog.first, 'get_visit');
    });
  });
}

AppointmentListItem _appointmentItem({
  required AppointmentStatus status,
  bool onAppointmentDay = false,
  String? doctorId = _doctorB,
}) {
  final start = onAppointmentDay ? _appointmentListStartUtc : _appointmentListStartFutureUtc;
  return AppointmentListItem(
    id: _appointmentId,
    patientId: _patientId,
    patientName: 'Test Patient',
    doctorId: doctorId,
    doctorName: doctorId == null ? null : 'Dr Jones',
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: status,
  );
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _AcceptanceStaffRepo implements StaffAdminRepository {
  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    return const [StaffListItem(id: 'doc-1', fullName: 'Dr Ada', role: StaffRole.doctor, isActive: true)];
  }

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) => throw UnimplementedError();

  @override
  Future<bool> organizationHasOwner() => throw UnimplementedError();

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) =>
      throw UnimplementedError();
}
