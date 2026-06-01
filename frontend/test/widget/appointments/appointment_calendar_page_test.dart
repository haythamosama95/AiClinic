import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/doctor_schedule_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_detail_page.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  group('Appointment calendar and doctor schedule pages', () {
    testWidgets('calendar shows controls and doctor filter', (tester) async {
      await tester.pumpWidget(_host(initialLocation: AppRoutes.appointmentsCalendar));
      await tester.pumpAndSettle();

      expect(find.text('Appointment calendar'), findsOneWidget);
      expect(find.byKey(const Key('appointments_calendar_doctor_filter')), findsOneWidget);
      expect(find.byKey(const Key('appointments_calendar_prev')), findsOneWidget);
      expect(find.byKey(const Key('appointments_calendar_next')), findsOneWidget);
    });

    testWidgets('doctor schedule route resolves and loads calendar', (tester) async {
      await tester.pumpWidget(_host(initialLocation: AppRoutes.appointmentsSchedule('doc-1')));
      await tester.pumpAndSettle();

      expect(find.text('Appointment calendar'), findsOneWidget);
      expect(find.byKey(const Key('appointments_calendar_today')), findsOneWidget);
    });

    testWidgets('navigation controls are enabled', (tester) async {
      await tester.pumpWidget(_host(initialLocation: AppRoutes.appointmentsCalendar));
      await tester.pumpAndSettle();

      final previousButton = tester.widget<OutlinedButton>(find.byKey(const Key('appointments_calendar_prev')));
      final nextButton = tester.widget<OutlinedButton>(find.byKey(const Key('appointments_calendar_next')));
      final todayButton = tester.widget<FilledButton>(find.byKey(const Key('appointments_calendar_today')));
      expect(previousButton.onPressed, isNotNull);
      expect(nextButton.onPressed, isNotNull);
      expect(todayButton.onPressed, isNotNull);
    });

    testWidgets('calendar handles duplicate branch ids in dropdown safely', (tester) async {
      await tester.pumpWidget(_host(initialLocation: AppRoutes.appointmentsCalendar, includeDuplicateBranch: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_calendar_branch_filter')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scheduled appointment sheet does not show Open Visit', (tester) async {
      await tester.pumpWidget(
        _host(
          initialLocation: AppRoutes.appointmentsCalendar,
          appointmentStatus: 'scheduled',
          visitPermissions: {PermissionKeys.visitsCreate},
          visitByAppointment: {'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'status': 'in_progress'},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_calendar_open_visit')), findsNothing);
      expect(find.text('Open patient record'), findsOneWidget);
    });

    testWidgets('completed appointment without linked visit hides Open Visit', (tester) async {
      await tester.pumpWidget(
        _host(
          initialLocation: AppRoutes.appointmentsCalendar,
          appointmentStatus: 'completed',
          visitPermissions: {PermissionKeys.visitsCreate},
          visitByAppointment: {'visit_id': null, 'status': null},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_calendar_open_visit')), findsNothing);
    });

    testWidgets('completed appointment hides Open Visit when visit lookup fails', (tester) async {
      await tester.pumpWidget(
        _host(
          initialLocation: AppRoutes.appointmentsCalendar,
          appointmentStatus: 'completed',
          visitPermissions: {PermissionKeys.visitsCreate},
          visitLookupFails: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_calendar_open_visit')), findsNothing);
    });

    testWidgets('completed appointment hides Open Visit without clinical visit permission', (tester) async {
      await tester.pumpWidget(
        _host(
          initialLocation: AppRoutes.appointmentsCalendar,
          appointmentStatus: 'completed',
          visitByAppointment: {'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'status': 'completed'},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_calendar_open_visit')), findsNothing);
    });

    testWidgets('completed appointment sheet shows Open Visit when linked visit exists', (tester) async {
      const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

      await tester.pumpWidget(
        _host(
          initialLocation: AppRoutes.appointmentsCalendar,
          appointmentStatus: 'completed',
          visitPermissions: {PermissionKeys.visitsCreate},
          visitByAppointment: {'visit_id': visitId, 'status': 'completed'},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointments_calendar_open_visit')), findsOneWidget);
      expect(find.text('Open patient record'), findsOneWidget);

      await tester.tap(find.byKey(const Key('appointments_calendar_open_visit')));
      await tester.pumpAndSettle();

      expect(find.byType(VisitDetailPage), findsOneWidget);
    });
  });
}

Widget _host({
  required String initialLocation,
  bool includeDuplicateBranch = false,
  String appointmentStatus = 'scheduled',
  Set<String> visitPermissions = const {},
  Map<String, dynamic>? visitByAppointment,
  bool visitLookupFails = false,
}) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, 9);
  final end = start.add(const Duration(minutes: 30));
  final branchId = '44444444-4444-4444-8444-444444444444';
  final authState = AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: {PermissionKeys.appointmentsCreate, ...visitPermissions},
      activeBranchId: branchId,
      branchIds: [branchId],
    ),
  );

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(authState)),
      appointmentRepositoryProvider.overrideWith(
        (ref) => AppointmentRepository(
          AppointmentRpcTestClient(
            rpcResults: {
              'list_appointments': {
                'success': true,
                'data': {
                  'items': [
                    {
                      'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                      'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
                      'patient_name': 'Test Patient',
                      'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
                      'doctor_name': 'Dr Test',
                      'start_time': start.toUtc().toIso8601String(),
                      'end_time': end.toUtc().toIso8601String(),
                      'type': 'planned',
                      'status': appointmentStatus,
                    },
                  ],
                },
              },
            },
          ),
        ),
      ),
      if (visitByAppointment != null || visitLookupFails)
        visitRepositoryProvider.overrideWith(
          (ref) => VisitRepository(
            VisitRpcTestClient(
              rpcResults: visitLookupFails
                  ? {
                      'get_visit_by_appointment': {
                        'success': false,
                        'error_code': 'INTERNAL',
                        'error_message': 'lookup failed',
                      },
                    }
                  : {
                      'get_visit_by_appointment': {'success': true, 'data': visitByAppointment},
                    },
            ),
          ),
        ),
      branchRepositoryProvider.overrideWithValue(
        _FakeBranchRepository(branchId: branchId, includeDuplicateBranch: includeDuplicateBranch),
      ),
      staffAdminRepositoryProvider.overrideWithValue(_FakeStaffAdminRepository()),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(path: AppRoutes.appointmentsCalendar, builder: (context, state) => const AppointmentCalendarPage()),
          GoRoute(
            path: '${AppRoutes.appointments}/schedule/:doctorId',
            builder: (context, state) => DoctorSchedulePage(doctorId: state.pathParameters['doctorId']),
          ),
          GoRoute(
            path: '${AppRoutes.patients}/:patientId',
            builder: (context, state) => const Scaffold(body: Text('Patient detail page')),
          ),
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}',
            builder: (context, state) => VisitDetailPage(visitId: state.pathParameters['visitId']),
          ),
        ],
      ),
    ),
  );
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _FakeStaffAdminRepository implements StaffAdminRepository {
  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    return const [
      StaffListItem(id: 'doc-1', fullName: 'Dr Test', role: StaffRole.doctor, isActive: true),
      StaffListItem(id: 'doc-2', fullName: 'Dr House', role: StaffRole.doctor, isActive: true),
    ];
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

class _FakeBranchRepository implements BranchRepository {
  _FakeBranchRepository({required this.branchId, this.includeDuplicateBranch = false});

  final String branchId;
  final bool includeDuplicateBranch;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    return [
      BranchListItem(id: branchId, name: 'Main Branch', isActive: true),
      if (includeDuplicateBranch) BranchListItem(id: branchId, name: 'Main Branch Duplicate', isActive: true),
    ];
  }

  @override
  Future<String> createBranch(CreateBranchInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) => throw UnimplementedError();

  @override
  Future<String> updateBranch(UpdateBranchInput input) => throw UnimplementedError();
}
