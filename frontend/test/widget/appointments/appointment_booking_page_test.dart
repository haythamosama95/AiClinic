import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_booking_page.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

Future<void> _pumpBookingPage(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('AppointmentBookingPage', () {
    testWidgets('trivial: pre-fills duration from appointment settings', (tester) async {
      await _pumpBookingPage(tester, _host());

      expect(find.text('Book appointment'), findsWidgets);
      expect(find.byKey(const Key('appointment_duration_field')), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('Duration (minutes)'), findsOneWidget);
    });

    testWidgets('advanced: RPC_NOT_CONFIGURED shows migration guidance on settings load', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['get_appointment_settings'] = {
          'success': false,
          'error_code': 'RPC_NOT_CONFIGURED',
          'error_message':
              'Appointment database permissions are incomplete. Apply migration: 20260527150000_grant_appointment_auth_internal_execute.sql',
        };

      await _pumpBookingPage(tester, _host(rpcClient: client));

      expect(find.textContaining('database permissions'), findsOneWidget);
      expect(find.textContaining('migrations'), findsOneWidget);
    });

    testWidgets('permission denied without appointments.create', (tester) async {
      await _pumpBookingPage(tester, _host(permissions: {PermissionKeys.patientsView}));

      expect(find.text('You do not have permission to book appointments.'), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_submit')), findsNothing);
    });

    testWidgets('advanced: SCHEDULE_CONFLICT shows conflict banner', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['create_appointment'] = {
          'success': false,
          'error_code': 'SCHEDULE_CONFLICT',
          'error_message': 'Overlap',
        };

      await _pumpBookingPage(tester, _host(rpcClient: client));

      await tester.enterText(find.byKey(const Key('patient_search_field')), 'Test');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('patient_picker_result_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('doctor_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dr Smith').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_booking_pick_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('conflict_error_banner')), findsOneWidget);
      expect(find.textContaining('overlaps another booked slot'), findsOneWidget);
    });

    testWidgets('advanced: book without doctor omits doctor id on RPC', (tester) async {
      final client = AppointmentRpcTestClient();

      await _pumpBookingPage(tester, _host(rpcClient: client));

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

      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'create_appointment');
      expect(client.lastParams?.containsKey('p_doctor_id'), isTrue);
      expect(client.lastParams?['p_doctor_id'], isNull);
      expect(find.textContaining('unexpected error'), findsNothing);
    });

    testWidgets('stupid usage: submit without patient shows validation message', (tester) async {
      await _pumpBookingPage(tester, _host());

      await tester.tap(find.byKey(const Key('doctor_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dr Smith').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Select a patient.'), findsOneWidget);
    });

    testWidgets('edge case: custom duration override is sent on book', (tester) async {
      final client = AppointmentRpcTestClient();

      await _pumpBookingPage(tester, _host(rpcClient: client));

      await tester.enterText(find.byKey(const Key('patient_search_field')), 'Test');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('patient_picker_result_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('doctor_selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dr Smith').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_booking_pick_start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('appointment_duration_field')), '45');
      await tester.pump();

      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(client.lastParams?['p_duration_minutes'], 45);
    });

    testWidgets('happy path: successful book shows confirmation', (tester) async {
      final client = AppointmentRpcTestClient();

      await _pumpBookingPage(tester, _host(rpcClient: client));
      await _fillMinimalBookingForm(tester);
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Appointment booked successfully.'), findsOneWidget);
      expect(client.lastFunction, 'create_appointment');
      expect(client.lastParams?['p_type'], 'planned');
    });

    testWidgets('stupid usage: submit without start time shows validation message', (tester) async {
      await _pumpBookingPage(tester, _host());

      await tester.enterText(find.byKey(const Key('patient_search_field')), 'Test');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('patient_picker_result_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Select a start date and time.'), findsOneWidget);
    });

    testWidgets('edge case: duration below minimum shows validation on form', (tester) async {
      await _pumpBookingPage(tester, _host());

      await tester.enterText(find.byKey(const Key('patient_search_field')), 'Test');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('patient_picker_result_0')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('appointment_duration_field')), '4');
      await tester.pump();

      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('between 5 and 240'), findsOneWidget);
    });

    testWidgets('advanced: INVALID_DOCTOR shows form error', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['create_appointment'] = {
          'success': false,
          'error_code': 'INVALID_DOCTOR',
          'error_message': 'Bad doctor',
        };

      await _pumpBookingPage(tester, _host(rpcClient: client));
      await _fillMinimalBookingForm(tester);
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('doctor'), findsOneWidget);
      expect(find.byKey(const Key('conflict_error_banner')), findsNothing);
    });

    testWidgets('advanced: PATIENT_ARCHIVED shows form error', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['create_appointment'] = {
          'success': false,
          'error_code': 'PATIENT_ARCHIVED',
          'error_message': 'Archived',
        };

      await _pumpBookingPage(tester, _host(rpcClient: client));
      await _fillMinimalBookingForm(tester);
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('archived'), findsOneWidget);
    });

    testWidgets('advanced: PATIENT_ALREADY_BOOKED_SAME_DAY shows form error', (tester) async {
      final client = AppointmentRpcTestClient()
        ..rpcResults['create_appointment'] = {
          'success': false,
          'error_code': 'PATIENT_ALREADY_BOOKED_SAME_DAY',
          'error_message': 'Already booked',
        };

      await _pumpBookingPage(tester, _host(rpcClient: client));
      await _fillMinimalBookingForm(tester);
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('same day'), findsOneWidget);
      expect(find.textContaining('existing appointment'), findsOneWidget);
    });
  });
}

Future<void> _fillMinimalBookingForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('patient_search_field')), 'Test');
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('patient_picker_result_0')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('doctor_selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Dr Smith').last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('appointment_booking_pick_start')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
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
  final branchId = '44444444-4444-4444-8444-444444444444';
  final routerConfig =
      router ??
      GoRouter(
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Scaffold(body: Text('Home shell')),
          ),
          GoRoute(path: AppRoutes.appointmentsBook, builder: (context, state) => const AppointmentBookingPage()),
        ],
        initialLocation: AppRoutes.appointmentsBook,
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
