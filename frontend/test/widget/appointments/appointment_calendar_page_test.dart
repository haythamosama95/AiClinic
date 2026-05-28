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
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('Appointment calendar and doctor schedule pages', () {
    testWidgets('calendar shows list results and doctor filter', (tester) async {
      await tester.pumpWidget(_host(initialLocation: AppRoutes.appointmentsCalendar));
      await tester.pumpAndSettle();

      expect(find.text('Appointment calendar'), findsOneWidget);
      expect(find.byKey(const Key('appointments_calendar_doctor_filter')), findsOneWidget);
      expect(find.text('Test Patient'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
    });

    testWidgets('doctor schedule route resolves and loads calendar', (tester) async {
      await tester.pumpWidget(_host(initialLocation: AppRoutes.appointmentsSchedule('doc-1')));
      await tester.pumpAndSettle();

      expect(find.text('Appointment calendar'), findsOneWidget);
      expect(find.text('Test Patient'), findsOneWidget);
    });

    testWidgets('pressing patient opens patient detail page', (tester) async {
      await tester.pumpWidget(_host(initialLocation: AppRoutes.appointmentsCalendar));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.text('Patient detail page'), findsOneWidget);
    });
  });
}

Widget _host({required String initialLocation}) {
  final branchId = '44444444-4444-4444-8444-444444444444';
  final authState = AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: {PermissionKeys.appointmentsCreate},
      activeBranchId: branchId,
      branchIds: [branchId],
    ),
  );

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(authState)),
      appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(AppointmentRpcTestClient())),
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
