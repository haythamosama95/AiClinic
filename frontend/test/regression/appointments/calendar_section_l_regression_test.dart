import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_schedule.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_clock_time_field.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart' as domain;
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/pump_auth_app.dart';
import '../../widget/appointments/appointment_calendar_test_support.dart';

void main() {
  group('CAL-L — regression', () {
    testWidgets('CAL-L01: AppClockTimeField updates when parent value changes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en', 'US'),
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: const _ClockTimeFieldHost(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('9:00 AM'), findsOneWidget);

      await tester.tap(find.text('Update time'));
      await tester.pump();
      await tester.pump();

      expect(find.text('9:00 AM'), findsNothing);
      expect(find.text('2:30 PM'), findsOneWidget);
    });

    test('CAL-L02: listAppointments repository contract unchanged by calendar work', () async {
      final client = AppointmentRpcTestClient();
      final repository = AppointmentRepository(client);

      final items = await repository.listAppointments(
        branchId: calendarTestBranchAId,
        from: DateTime.utc(2026, 6, 1),
        to: DateTime.utc(2026, 6, 2),
      );

      expect(client.lastFunction, 'list_appointments');
      expect(items, hasLength(1));
      expect(items.first.patientName, 'Test Patient');
    });

    test('CAL-L03: dev seed appointment slots stay within branch hours for calendar display', () {
      ensureAppointmentTimezonesInitialized();
      final referenceUtc = DateTime.utc(2026, 6, 13, 12);
      final location = tz.getLocation('Africa/Cairo');

      for (final dayOffset in DevClinicSeedSchedule.appointmentDayOffsets) {
        for (var patientIndex = 1; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
          final startUtc = DevClinicSeedSchedule.appointmentStartUtc(
            timezone: 'Africa/Cairo',
            dayOffset: dayOffset,
            patientIndex: patientIndex,
            hasSecondaryDoctor: false,
            referenceUtc: referenceUtc,
          );
          final duration = DevClinicSeedSchedule.appointmentDurationMinutesFor(patientIndex + dayOffset);
          final startLocal = tz.TZDateTime.from(startUtc, location);
          final endLocal = startLocal.add(Duration(minutes: duration));

          expect(startLocal.hour, greaterThanOrEqualTo(9));
          expect(endLocal.hour, lessThanOrEqualTo(DevClinicSeedSchedule.branchCloseLocalHour));
        }
      }
    });

    test('CAL-L04: repository rejects duration below 5 minutes before RPC', () async {
      final client = AppointmentRpcTestClient();
      final repository = AppointmentRepository(client);

      expect(
        () => repository.createAppointment(
          branchId: calendarTestBranchAId,
          patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          doctorId: calendarTestDoctorAId,
          type: domain.AppointmentType.planned,
          startTime: DateTime.utc(2026, 6, 1, 10),
          durationMinutes: 4,
        ),
        throwsA(isA<RpcFailure>().having((error) => error.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.createAppointmentCalls, isEmpty);
    });

    testWidgets('CAL-L05: shell navigation away and back keeps calendar usable', (tester) async {
      final client = AppointmentRpcTestClient();

      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(
            () => PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {PermissionKeys.appointmentsRead}),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(CalendarStubBranchRepository())),
          listStaffUseCaseProvider.overrideWith((ref) => ListStaff(CalendarStubStaffRepository())),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.appointmentsCalendar);
      await tester.pump();
      await settleCalendarWidgetTest(tester);

      expect(find.byType(AppointmentCalendarPage), findsOneWidget);
      expect(find.byType(SfCalendar), findsOneWidget);

      container.read(appRouterProvider).go(AppRoutes.patients);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.patients);

      container.read(appRouterProvider).go(AppRoutes.appointmentsCalendar);
      await tester.pump();
      await settleCalendarWidgetTest(tester);

      expect(find.byType(AppointmentCalendarPage), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.byType(SfCalendar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('CAL-L06: permission service appointment grants remain stable', () {
      final readOnly = PermissionService(sampleAuthSessionContext(permissions: {PermissionKeys.appointmentsRead}));
      expect(readOnly.canAccessAppointments(), isTrue);
      expect(readOnly.canCreateAppointments(), isFalse);

      final creator = PermissionService(
        sampleAuthSessionContext(permissions: {PermissionKeys.appointmentsCreate, PermissionKeys.appointmentsRead}),
      );
      expect(creator.canAccessAppointments(), isTrue);
      expect(creator.canCreateAppointments(), isTrue);
    });
  });
}

class _ClockTimeFieldHost extends StatefulWidget {
  const _ClockTimeFieldHost();

  @override
  State<_ClockTimeFieldHost> createState() => _ClockTimeFieldHostState();
}

class _ClockTimeFieldHostState extends State<_ClockTimeFieldHost> {
  TimeOfDay _value = const TimeOfDay(hour: 9, minute: 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppClockTimeField(label: 'Start', value: _value),
          TextButton(
            onPressed: () => setState(() => _value = const TimeOfDay(hour: 14, minute: 30)),
            child: const Text('Update time'),
          ),
        ],
      ),
    );
  }
}
