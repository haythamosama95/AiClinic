import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_calendar_test_support.dart';

const _detailPatientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

PatientDetail calendarDetailPatient() {
  return samplePatientDetail(id: _detailPatientId, fullName: 'Test Patient', branchId: calendarTestBranchAId);
}

Future<void> pumpCalendarWithPatientRoutes(WidgetTester tester, {AppointmentRpcTestClient? rpcClient}) async {
  final client = rpcClient ?? AppointmentRpcTestClient();
  final patientRepo = FakePatientRepository(detail: calendarDetailPatient());

  await tester.binding.setSurfaceSize(calendarWidgetSurfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: AppRoutes.appointmentsCalendar,
    routes: [
      GoRoute(
        path: AppRoutes.appointmentsCalendar,
        builder: (context, state) => const Scaffold(body: AppointmentCalendarPage()),
      ),
      GoRoute(
        path: '${AppRoutes.patients}/:patientId',
        builder: (context, state) {
          final patientId = state.pathParameters['patientId']!;
          final routeExtra = PatientDetailRouteExtra.fromExtra(state.extra);
          return Scaffold(
            body: PatientDetailPage(patientId: patientId, preview: routeExtra.preview),
          );
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(calendarAuthStateWithCreate())),
        appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        patientRepositoryProvider.overrideWithValue(patientRepo),
        listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(CalendarStubBranchRepository())),
        listStaffUseCaseProvider.overrideWith((ref) => ListStaff(CalendarStubStaffRepository())),
      ],
      child: ForuiAppScope(
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pump();
}

Appointment _firstMappedAppointment(WidgetTester tester) {
  final calendar = calendarWidget(tester);
  final dataSource = calendar.dataSource! as AppointmentCalendarDataSource;
  final appointments = dataSource.appointments;
  expect(appointments, isNotEmpty);
  return appointments!.first;
}

String expectedAppointmentRangeLabel(DateTime startLocal, DateTime endLocal) {
  final day = DateFormat.yMMMd().format(startLocal);
  final timeFormat = DateFormat('h:mm a');
  return '$day · ${timeFormat.format(startLocal)} – ${timeFormat.format(endLocal)}';
}

void main() {
  group('AppointmentCalendarPage detail sheet', () {
    group('CAL-F — appointment detail sheet', () {
      testWidgets('CAL-F01: appointment tile opens detail sheet with patient, doctor, time, status', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');
        await waitForAppointmentTileReveal(tester);

        final appointment = _firstMappedAppointment(tester);
        await tapFirstCalendarAppointment(tester);

        expect(find.text('Test Patient'), findsWidgets);
        expect(find.text('Dr Test'), findsOneWidget);
        expect(find.text('Scheduled'), findsOneWidget);
        expect(find.text(expectedAppointmentRangeLabel(appointment.startTime, appointment.endTime)), findsOneWidget);
        expect(find.text('Open patient'), findsOneWidget);
      });

      testWidgets('CAL-F02: Open patient navigates to patient detail', (tester) async {
        await pumpCalendarWithPatientRoutes(tester);
        await waitForCalendarLoaded(tester);
        await tapCalendarViewTab(tester, 'Day');
        await waitForAppointmentTileReveal(tester);

        await tapFirstCalendarAppointment(tester);
        await tester.tap(find.text('Open patient'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(PatientDetailPage), findsOneWidget);
      });

      testWidgets('CAL-F03: appointment detail opens after skeleton reveal delay', (tester) async {
        await pumpAppointmentCalendarPage(tester, authState: calendarAuthState());
        final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentCalendarPage)));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          final state = container.read(appointmentCalendarProvider);
          if (!state.loading && state.items.isNotEmpty) {
            break;
          }
        }

        await tester.pump(const Duration(milliseconds: 200));
        await tapCalendarViewTab(tester, 'Day');
        await tapFirstCalendarAppointment(tester);
        expect(find.text('Open patient'), findsOneWidget);
      });
    });
  });
}
