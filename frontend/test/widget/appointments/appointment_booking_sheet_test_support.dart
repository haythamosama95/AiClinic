import 'dart:async';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/patient_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/fake_postgrest_rpc.dart';
import 'appointment_calendar_test_support.dart';

/// Suppresses known ListTile background color assertion noise in booking sheet tests.
void suppressBookingSheetListTileNoise() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('ListTile background color')) {
      return;
    }
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);
}

/// Delays [create_appointment] responses for double-submit tests.
class SlowCreateAppointmentRpcClient extends AppointmentRpcTestClient {
  SlowCreateAppointmentRpcClient({this.createDelay = const Duration(milliseconds: 500)});

  final Duration createDelay;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'create_appointment') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      if (lastParams != null) {
        createAppointmentCalls.add(Map<String, dynamic>.from(lastParams!));
      }
      final payload =
          rpcResults[fn] ??
          {
            'success': true,
            'data': {
              'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'start_time': '2026-06-01T10:00:00.000Z',
              'end_time': '2026-06-01T10:30:00.000Z',
              'status': 'scheduled',
              'type': lastParams?['p_type'] ?? 'planned',
            },
          };
      return _DelayedFakePostgrestRpc(payload, createDelay) as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _DelayedFakePostgrestRpc extends FakePostgrestRpc {
  _DelayedFakePostgrestRpc(super.result, this.delay);

  final Duration delay;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<void>.delayed(delay).then((_) => super.then(onValue, onError: onError));
  }
}

Future<void> pumpAppointmentBookingSheet(
  WidgetTester tester, {
  required AppointmentRpcTestClient client,
  required DateTime slotStart,
  required DateTime slotEnd,
  FakePatientRepository? patientRepository,
  List<StaffListItem> doctors = const [],
  String? initialDoctorId,
  BranchWorkingSchedule? schedule,
  bool useModalOverlay = false,
}) async {
  suppressBookingSheetListTileNoise();

  await tester.binding.setSurfaceSize(calendarWidgetSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final patients = patientRepository ?? FakePatientRepository();
  final branchSchedule = schedule ?? BranchWorkingSchedule.defaultSchedule();

  if (useModalOverlay) {
    late BuildContext hostContext;
    await tester.pumpWidget(
      ProviderScope(
        overrides: bookingSheetOverrides(client: client, patientRepository: patients),
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );
    await tester.pump();
    unawaited(
      AppointmentBookingSheet.show(
        hostContext,
        branchId: calendarTestBranchAId,
        schedule: branchSchedule,
        slotStart: slotStart,
        slotEnd: slotEnd,
        initialDoctorId: initialDoctorId,
        doctors: doctors,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return;
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: bookingSheetOverrides(client: client, patientRepository: patients),
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child!),
        home: Scaffold(
          body: AppointmentBookingSheet(
            branchId: calendarTestBranchAId,
            schedule: branchSchedule,
            slotStart: slotStart,
            slotEnd: slotEnd,
            initialDoctorId: initialDoctorId,
            doctors: doctors,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<Override> bookingSheetOverrides({
  required AppointmentRpcTestClient client,
  required FakePatientRepository patientRepository,
}) {
  return [
    authSessionProvider.overrideWith(
      () => PresetAuthSessionNotifier(
        calendarAuthState(permissions: {PermissionKeys.appointmentsCreate, PermissionKeys.appointmentsRead}),
      ),
    ),
    appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
    patientRepositoryProvider.overrideWithValue(patientRepository),
    searchPatientsUseCaseProvider.overrideWith((ref) => SearchPatients(ref.watch(patientRepositoryProvider))),
  ];
}

Future<void> waitForBookingSheetReady(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byKey(const Key('appointment_booking_submit')).evaluate().isNotEmpty) {
      return;
    }
    if (find.text('Retry').evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Booking sheet did not finish loading settings.');
}

Future<void> searchAndSelectPatient(WidgetTester tester, {required String query, required String patientName}) async {
  await tester.enterText(find.byKey(const Key('appointment_booking_patient_search')), query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();

  await tester.tap(find.text(patientName));
  await tester.pumpAndSettle();
}

Future<void> tapBookingSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('appointment_booking_submit')));
  await tester.tap(find.byKey(const Key('appointment_booking_submit')));
  await tester.pump();
}

Future<void> submitValidBooking(
  WidgetTester tester, {
  required PatientListItem patient,
  String searchQuery = 'Pat',
}) async {
  await searchAndSelectPatient(tester, query: searchQuery, patientName: patient.fullName);
  await tapBookingSubmit(tester);
  await tester.pumpAndSettle();
}

/// Fixed Monday used for deterministic booking validation tests.
DateTime bookingTestMonday({int hour = 10, int minute = 0}) {
  return DateTime(2026, 6, 15, hour, minute);
}
