// US1 smoke: spec cases 1–2, 7, and 14 (booking portion) with fake RPC — not full acceptance (T062).
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_booking_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart' show staffAdminRepositoryProvider;
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

Future<void> _pumpUs1Host(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('Appointment booking US1 integration smoke', () {
    testWidgets('case 1 partial: book planned shows success', (tester) async {
      final client = AppointmentRpcTestClient();
      await _pumpUs1Host(tester, _host(client: client));

      expect(find.text('20'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('patient_search_field')), 'Test');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('patient_picker_result_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_booking_pick_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('appointment_duration_field')), '30');
      await tester.pump();

      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Appointment booked successfully.'), findsOneWidget);
      expect(client.lastParams?['p_duration_minutes'], 30);
    });

    testWidgets('case 2: schedule conflict shows banner', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['create_appointment'] = {
          'success': false,
          'error_code': 'SCHEDULE_CONFLICT',
          'error_message': 'Overlap',
        };

      await _pumpUs1Host(tester, _host(client: client));

      await tester.enterText(find.byKey(const Key('patient_search_field')), 'Test');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('patient_picker_result_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appointment_booking_pick_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final submit = find.byKey(const Key('appointment_booking_submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('conflict_error_banner')), findsOneWidget);
    });

    testWidgets('case 7: user without create sees permission denied', (tester) async {
      await _pumpUs1Host(tester, _host(permissions: {PermissionKeys.patientsView}));

      expect(find.text('You do not have permission to book appointments.'), findsOneWidget);
    });
  });
}

Widget _host({
  AppointmentRpcTestClient? client,
  Set<String> permissions = const {PermissionKeys.appointmentsCreate, PermissionKeys.patientsView},
}) {
  final rpcClient = client ?? AppointmentRpcTestClient();
  final branchId = '44444444-4444-4444-8444-444444444444';

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuth(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              permissions: permissions,
              activeBranchId: branchId,
              branchIds: [branchId],
            ),
          ),
        ),
      ),
      appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(rpcClient)),
      patientRepositoryProvider.overrideWith((ref) => FakePatientRepository(patients: [samplePatientListItem()])),
      staffAdminRepositoryProvider.overrideWithValue(_SmokeStaffRepoWithDoctor()),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: AppRoutes.appointmentsBook,
        routes: [GoRoute(path: AppRoutes.appointmentsBook, builder: (_, _) => const AppointmentBookingPage())],
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

class _SmokeStaffRepoWithDoctor implements StaffAdminRepository {
  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    return const [
      StaffListItem(
        id: '22222222-2222-4222-8222-222222222222',
        fullName: 'Dr Smith',
        role: StaffRole.doctor,
        isActive: true,
      ),
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
