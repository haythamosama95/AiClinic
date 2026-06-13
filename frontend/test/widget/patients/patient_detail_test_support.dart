import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart' as domain;
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_container_transform_transition.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patients_page.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/visit_rpc_test_client.dart';

const patientDetailTestId = '11111111-1111-4111-8111-111111111111';

PatientDetail sampleDetailForWidgetTests({String? notes}) {
  return PatientDetail(
    id: patientDetailTestId,
    fullName: 'Sara Ali',
    phone: '201111111111',
    dateOfBirth: DateTime.utc(1985, 3, 20),
    gender: PatientGender.female,
    maritalStatus: PatientMaritalStatus.married,
    notes: notes ?? 'Allergic to penicillin',
    branchId: testBranchAId,
    branchName: 'Main',
    createdAt: DateTime.utc(2026, 1, 1, 8),
    updatedAt: DateTime.utc(2026, 1, 2, 9, 30),
    createdByDisplay: 'Reception',
  );
}

PatientListItem samplePreviewForWidgetTests() {
  return PatientListItem(
    id: patientDetailTestId,
    fullName: 'Sara Ali',
    phone: '201111111111',
    dateOfBirth: DateTime.utc(1985, 3, 20),
    gender: PatientGender.female,
    registeringBranchId: testBranchAId,
    registeringBranchName: 'Main',
  );
}

List<Map<String, dynamic>> samplePastVisitItems() {
  return [
    {
      'id': '22222222-2222-4222-8222-222222222222',
      'visit_date': '2026-05-20T09:00:00.000Z',
      'doctor_name': 'Dr Ahmed',
      'status': 'completed',
      'branch_name': 'Main',
    },
    {
      'id': '33333333-3333-4333-8333-333333333333',
      'visit_date': '2026-04-10T14:30:00.000Z',
      'doctor_name': 'Dr Sara',
      'status': 'completed',
      'branch_name': 'Downtown',
    },
  ];
}

List<Map<String, dynamic>> sampleUpcomingAppointmentItems() {
  return [
    {
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'patient_id': patientDetailTestId,
      'patient_name': 'Sara Ali',
      'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'doctor_name': 'Dr Future',
      'start_time': '2026-08-01T09:00:00.000Z',
      'end_time': '2026-08-01T09:30:00.000Z',
      'type': 'planned',
      'status': 'scheduled',
    },
    {
      'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'patient_id': patientDetailTestId,
      'patient_name': 'Sara Ali',
      'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'doctor_name': 'Dr Later',
      'start_time': '2026-09-15T14:00:00.000Z',
      'end_time': '2026-09-15T14:30:00.000Z',
      'type': 'planned',
      'status': 'confirmed',
    },
  ];
}

List<Map<String, dynamic>> sampleDocumentAttachmentItems({bool canDownload = true}) {
  return [
    {
      'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'visit_date': '2026-05-31',
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'file_type': 'pdf',
      'label': 'Lab PDF',
      'uploaded_by': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'uploaded_by_name': 'Dr Test',
      'size_bytes': 1024,
      'created_at': '2026-05-31T10:00:00.000Z',
      'can_download': canDownload,
    },
  ];
}

/// Visit repository that fails [failListVisitsUntil] times before delegating.
class FlakyVisitRepository extends VisitRepository {
  FlakyVisitRepository(super.client, {this.failListVisitsUntil = 1});

  final int failListVisitsUntil;
  var listVisitsCallCount = 0;

  @override
  Future<PatientVisitsPage> listPatientVisits({required String patientId, int limit = 50, int offset = 0}) async {
    listVisitsCallCount++;
    if (listVisitsCallCount <= failListVisitsUntil) {
      throw StateError('Temporary visit load failure');
    }
    return super.listPatientVisits(patientId: patientId, limit: limit, offset: offset);
  }
}

Future<void> pumpPatientDetailPage(
  WidgetTester tester,
  Widget widget, {
  Size surfaceSize = const Size(1280, 900),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
}

Future<void> settlePatientDetail(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> setDetailViewport(WidgetTester tester, double width, {double height = 900}) async {
  await tester.binding.setSurfaceSize(Size(width, height));
  await tester.pumpAndSettle();
}

/// Notes card is to the right of the timeline section (wide/medium split layout).
bool isNotesRightOfTimeline(WidgetTester tester) {
  final notesX = tester.getTopLeft(find.text('Notes')).dx;
  final timelineX = tester.getTopLeft(find.text('Past visits')).dx;
  return notesX > timelineX;
}

Future<void> confirmPatientDelete(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(AppButton, 'Delete patient'));
  await tester.pumpAndSettle();
}

Future<void> cancelPatientDelete(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
  await tester.pumpAndSettle();
}

Future<void> tapPatientDeleteHeader(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Delete patient'));
  await tester.pumpAndSettle();
}

/// Notes card appears above the timeline (compact stacked layout).
bool isNotesAboveTimeline(WidgetTester tester) {
  final notesY = tester.getTopLeft(find.text('Notes')).dy;
  final timelineY = tester.getTopLeft(find.text('Past visits')).dy;
  return notesY < timelineY;
}

List<Override> patientDetailOverrides({
  domain.PatientRepository? repository,
  PatientDetail? detail,
  Future<PatientDetail> Function(String patientId)? getPatient,
  List<Map<String, dynamic>> visitItems = const [],
  List<Map<String, dynamic>> appointmentItems = const [],
  List<Map<String, dynamic>> documentItems = const [],
  VisitRpcTestClient? visitClient,
  AppointmentRpcTestClient? appointmentClient,
  FlakyVisitRepository? flakyVisitRepository,
  Set<String> permissions = const {'patients.view'},
}) {
  final domain.PatientRepository repo;
  if (repository != null) {
    repo = repository;
  } else if (getPatient != null) {
    repo = _CallbackPatientRepository(getPatient);
  } else {
    repo = FakePatientRepository(detail: detail ?? sampleDetailForWidgetTests());
  }

  final visits =
      visitClient ??
      VisitRpcTestClient(
        rpcResults: {
          if (visitItems.isNotEmpty)
            'list_patient_visits': {
              'success': true,
              'data': {'items': visitItems, 'total_count': visitItems.length, 'limit': 50, 'offset': 0},
            },
          if (documentItems.isNotEmpty)
            'list_patient_visit_attachments': {
              'success': true,
              'data': {'items': documentItems, 'total_count': documentItems.length, 'limit': 100, 'offset': 0},
            },
        },
      );

  final appointments =
      appointmentClient ??
      AppointmentRpcTestClient(
        rpcResults: {
          'list_appointments': {
            'success': true,
            'data': {'items': appointmentItems},
          },
        },
      );

  return [
    authSessionProvider.overrideWith(() => _PatientDetailAuthNotifier(permissions)),
    patientRepositoryProvider.overrideWith((ref) => repo),
    visitRepositoryProvider.overrideWith((ref) => flakyVisitRepository ?? VisitRepository(visits)),
    appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(appointments)),
  ];
}

Widget patientDetailHost({
  domain.PatientRepository? repository,
  PatientDetail? detail,
  Future<PatientDetail> Function(String patientId)? getPatient,
  PatientListItem? preview,
  List<Map<String, dynamic>> visitItems = const [],
  List<Map<String, dynamic>> appointmentItems = const [],
  List<Map<String, dynamic>> documentItems = const [],
  VisitRpcTestClient? visitClient,
  AppointmentRpcTestClient? appointmentClient,
  FlakyVisitRepository? flakyVisitRepository,
  Set<String> permissions = const {'patients.view'},
  Size surfaceSize = const Size(1280, 900),
}) {
  return ProviderScope(
    overrides: patientDetailOverrides(
      repository: repository,
      detail: detail,
      getPatient: getPatient,
      visitItems: visitItems,
      appointmentItems: appointmentItems,
      documentItems: documentItems,
      visitClient: visitClient,
      appointmentClient: appointmentClient,
      flakyVisitRepository: flakyVisitRepository,
      permissions: permissions,
    ),
    child: ForuiAppScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: PatientDetailPage(patientId: patientDetailTestId, preview: preview),
      ),
    ),
  );
}

/// Router with patients list + detail routes for navigation tests.
GoRouter patientDetailTestRouter({String initialLocation = AppRoutes.patients}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.patients,
        builder: (context, state) => const Scaffold(body: PatientsPage()),
      ),
      GoRoute(
        path: '${AppRoutes.patients}/:patientId',
        pageBuilder: (context, state) {
          final patientId = state.pathParameters['patientId']!;
          final routeExtra = PatientDetailRouteExtra.fromExtra(state.extra);
          return PatientDetailContainerTransformPage(
            state: state,
            sourceRect: routeExtra.sourceRect,
            child: PatientDetailPage(patientId: patientId, preview: routeExtra.preview),
          );
        },
      ),
    ],
  );
}

Widget patientDetailRouterHost({
  required GoRouter router,
  FakePatientRepository? patientsRepository,
  Set<String> permissions = const {'patients.view'},
  List<Map<String, dynamic>> visitItems = const [],
  List<Map<String, dynamic>> appointmentItems = const [],
  List<Map<String, dynamic>> documentItems = const [],
}) {
  return ProviderScope(
    overrides: [
      ...patientDetailOverrides(
        repository: patientsRepository,
        detail: patientsRepository?.detail,
        visitItems: visitItems,
        appointmentItems: appointmentItems,
        documentItems: documentItems,
        permissions: permissions,
      ),
      clinicSetupBranchesProvider.overrideWith(
        (ref) async => const [
          BranchListItem(id: testBranchAId, name: 'Branch A', code: 'A1', isActive: true),
          BranchListItem(id: testBranchBId, name: 'Branch B', code: 'B1', isActive: true),
        ],
      ),
    ],
    child: ForuiAppScope(
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ),
  );
}

class _PatientDetailAuthNotifier extends TestAuthSessionNotifier {
  _PatientDetailAuthNotifier(this._permissions);

  final Set<String> _permissions;

  @override
  AuthSessionState build() {
    return AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(permissions: _permissions),
    );
  }
}

class _CallbackPatientRepository implements domain.PatientRepository {
  _CallbackPatientRepository(this._getPatient);

  final Future<PatientDetail> Function(String patientId) _getPatient;

  @override
  Future<PatientDetail> getPatient(String patientId) => _getPatient(patientId);

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
  Future<PatientSearchPage> searchPatients({
    String? query,
    required PatientListScope scope,
    String? branchId,
    int limit = 25,
    int offset = 0,
    PatientLastVisitFilter lastVisitFilter = PatientLastVisitFilter.any,
    PatientSortField sortField = PatientSortField.nameAsc,
  }) => throw UnimplementedError();

  @override
  Future<DateTime> updatePatient(UpdatePatientInput input) => throw UnimplementedError();
}
