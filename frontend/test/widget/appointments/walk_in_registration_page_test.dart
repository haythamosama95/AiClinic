import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/walk_in_registration_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
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

Future<void> _pumpWalkInPage(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('WalkInRegistrationPage', () {
    testWidgets('trivial: pre-fills duration from settings', (tester) async {
      await _pumpWalkInPage(tester, _host());

      expect(find.text('Register walk-in'), findsWidgets);
      expect(find.byKey(const Key('appointment_duration_field')), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('advanced: success displays assigned slot card', (tester) async {
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

      await _pumpWalkInPage(tester, _host(rpcClient: client));
      await _fillWalkInForm(tester);
      await tester.tap(find.byKey(const Key('walk_in_registration_submit')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'create_appointment');
      expect(client.lastParams?['p_type'], AppointmentType.walkIn.wireValue);
      expect(find.byKey(const Key('walk_in_assigned_slot_card')), findsOneWidget);
      expect(find.text('Status: Checked in'), findsOneWidget);
    });

    testWidgets('advanced: submit without doctor still creates walk-in', (tester) async {
      await _pumpWalkInPage(tester, _host());

      await tester.enterText(find.byKey(const Key('patient_search_field')), 'Test');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('patient_picker_result_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('walk_in_registration_submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('walk_in_assigned_slot_card')), findsOneWidget);
    });

    testWidgets('edge case: duration below minimum shows validator message', (tester) async {
      await _pumpWalkInPage(tester, _host());
      await _fillWalkInForm(tester);
      await tester.enterText(find.byKey(const Key('appointment_duration_field')), '4');
      await tester.pump();

      await tester.tap(find.byKey(const Key('walk_in_registration_submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('between 5 and 240'), findsOneWidget);
    });

    testWidgets('stupid usage: submit without patient shows error', (tester) async {
      await _pumpWalkInPage(tester, _host());

      await tester.tap(find.byKey(const Key('doctor_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dr Smith').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('walk_in_registration_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Select a patient.'), findsOneWidget);
    });

    testWidgets('regression: NO_SLOT_AVAILABLE displays mapped user message', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['create_appointment'] = {
          'success': false,
          'error_code': 'NO_SLOT_AVAILABLE',
          'error_message': 'No free slot today',
        };

      await _pumpWalkInPage(tester, _host(rpcClient: client));
      await _fillWalkInForm(tester);
      await tester.tap(find.byKey(const Key('walk_in_registration_submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('No walk-in slot is available today'), findsOneWidget);
      expect(find.byKey(const Key('walk_in_assigned_slot_card')), findsNothing);
    });
  });
}

Future<void> _fillWalkInForm(WidgetTester tester) async {
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

class _FakeStaffAdminRepository implements StaffAdminRepository {
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

Widget _host({
  AppointmentRpcTestClient? rpcClient,
  Set<String> permissions = const {PermissionKeys.appointmentsCreate, PermissionKeys.patientsView},
  GoRouter? router,
}) {
  final client = rpcClient ?? AppointmentRpcTestClient();
  const branchId = '44444444-4444-4444-8444-444444444444';
  final routerConfig =
      router ??
      GoRouter(
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Scaffold(body: Text('Home shell')),
          ),
          GoRoute(path: AppRoutes.appointmentsWalkIn, builder: (context, state) => const WalkInRegistrationPage()),
        ],
        initialLocation: AppRoutes.appointmentsWalkIn,
      );

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
      appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
      patientRepositoryProvider.overrideWith((ref) => FakePatientRepository(patients: [samplePatientListItem()])),
      staffAdminRepositoryProvider.overrideWithValue(_FakeStaffAdminRepository()),
    ],
    child: MaterialApp.router(routerConfig: routerConfig),
  );
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
