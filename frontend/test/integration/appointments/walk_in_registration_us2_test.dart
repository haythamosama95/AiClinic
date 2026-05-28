import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/walk_in_registration_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart' show staffAdminRepositoryProvider;
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

Future<void> _pumpUs2Host(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('Walk-in registration US2 integration smoke', () {
    testWidgets('case 3 partial: walk-in registration shows assigned checked-in slot', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['create_appointment'] = {
          'success': true,
          'data': {
            'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'start_time': '2026-06-01T14:00:00.000Z',
            'end_time': '2026-06-01T14:20:00.000Z',
            'status': 'checked_in',
            'type': 'walk_in',
          },
        };

      await _pumpUs2Host(tester, _host(client: client));
      await tester.enterText(find.byKey(const Key('patient_search_field')), 'Test');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('patient_picker_result_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('walk_in_registration_submit')));
      await tester.pumpAndSettle();

      expect(client.lastParams?['p_type'], 'walk_in');
      expect(client.lastParams?['p_doctor_id'], isNull);
      expect(client.lastParams?.containsKey('p_start_time'), isFalse);
      expect(find.byKey(const Key('walk_in_assigned_slot_card')), findsOneWidget);
    });

    testWidgets('case 11 partial: no slot available is surfaced to user', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['create_appointment'] = {
          'success': false,
          'error_code': 'NO_SLOT_AVAILABLE',
          'error_message': 'No free slot',
        };

      await _pumpUs2Host(tester, _host(client: client));
      await _fillForm(tester);
      await tester.tap(find.byKey(const Key('walk_in_registration_submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('No walk-in slot is available today'), findsOneWidget);
      expect(find.byKey(const Key('walk_in_assigned_slot_card')), findsNothing);
    });
  });
}

Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('patient_search_field')), 'Test');
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('patient_picker_result_0')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('doctor_selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Dr Smith').last);
  await tester.pumpAndSettle();
}

Widget _host({
  AppointmentRpcTestClient? client,
  Set<String> permissions = const {PermissionKeys.appointmentsCreate, PermissionKeys.patientsView},
}) {
  final rpcClient = client ?? AppointmentRpcTestClient();
  const branchId = '44444444-4444-4444-8444-444444444444';

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
        initialLocation: AppRoutes.appointmentsWalkIn,
        routes: [GoRoute(path: AppRoutes.appointmentsWalkIn, builder: (_, _) => const WalkInRegistrationPage())],
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
