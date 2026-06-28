import 'dart:async';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_booking_flow.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../helpers/patient_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_booking_sheet_test_support.dart';
import 'appointment_calendar_test_support.dart';

const _simplifiedFlowTestDoctors = [
  StaffListItem(
    id: calendarTestDoctorAId,
    fullName: 'Dr. Ada',
    role: StaffRole.doctor,
    isActive: true,
    branches: [StaffBranchLabel(id: calendarTestBranchAId, name: 'Branch A', isPrimary: true)],
  ),
  StaffListItem(
    id: calendarTestDoctorBId,
    fullName: 'Dr. Ben',
    role: StaffRole.doctor,
    isActive: true,
    branches: [StaffBranchLabel(id: calendarTestBranchAId, name: 'Branch A', isPrimary: true)],
  ),
];

void main() {
  group('SimplifiedBookingFlow', () {
    Future<void> pumpFlow(
      WidgetTester tester, {
      required AppointmentRpcTestClient client,
      FakePatientRepository? patientRepository,
      List<StaffListItem> doctors = _simplifiedFlowTestDoctors,
    }) async {
      suppressBookingSheetListTileNoise();
      await tester.binding.setSurfaceSize(calendarWidgetSurfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final patients = patientRepository ?? FakePatientRepository();
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
        SimplifiedBookingFlow.show(
          hostContext,
          branchId: calendarTestBranchAId,
          schedule: BranchWorkingSchedule.defaultSchedule(),
          doctors: doctors,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> waitForStepTwo(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Select Date and Time').evaluate().isNotEmpty) {
          return;
        }
      }
      fail('Step two did not load.');
    }

    Future<void> waitForSlotsLoaded(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Select Date and Time').evaluate().isNotEmpty &&
            find.byType(AppCircularProgress).evaluate().isEmpty) {
          return;
        }
      }
      fail('Slots did not finish loading.');
    }

    Future<void> completeStepOne(
      WidgetTester tester, {
      required PatientListItem patient,
      String searchQuery = 'Pat',
      String doctorName = 'Dr. Ada',
    }) async {
      await tester.enterText(find.byKey(const Key('simplified_booking_patient_search')), searchQuery);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await tester.tap(find.text(patient.fullName));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppSelect<String>, 'Doctor (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(doctorName));
      await tester.pumpAndSettle();

      final nextFinder = find.byKey(const Key('simplified_booking_step_one_next'));
      await tester.ensureVisible(nextFinder);
      await tester.pumpAndSettle();
      await tester.tap(nextFinder);
      await tester.pump();
      await waitForStepTwo(tester);
      await waitForSlotsLoaded(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('step one blocks next without patient', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        await pumpFlow(tester, client: client);

        expect(find.text('Step 1 / 2'), findsOneWidget);
        final next = tester.widget<AppButton>(find.byKey(const Key('simplified_booking_step_one_next')));
        expect(next.onPressed, isNull);
      });
    });

    testWidgets('step one allows next with patient only', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'No Doctor Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );

        await tester.enterText(find.byKey(const Key('simplified_booking_patient_search')), 'No Doc');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await tester.tap(find.text(patient.fullName));
        await tester.pumpAndSettle();

        final next = tester.widget<AppButton>(find.byKey(const Key('simplified_booking_step_one_next')));
        expect(next.onPressed, isNotNull);
      });
    });

    testWidgets('step two without preferred doctor shows branch-wide slots without yellow chips', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'No Doctor Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );

        await tester.enterText(find.byKey(const Key('simplified_booking_patient_search')), 'No Doc');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await tester.tap(find.text(patient.fullName));
        await tester.pumpAndSettle();

        final nextFinder = find.byKey(const Key('simplified_booking_step_one_next'));
        await tester.ensureVisible(nextFinder);
        await tester.tap(nextFinder);
        await tester.pump();
        await waitForStepTwo(tester);
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();

        final slotLabel = DateFormat.jm().format(DateTime(2026, 6, 27, 10));
        expect(find.text(slotLabel), findsOneWidget);
        expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);
        expect(find.text('Other doctors free'), findsNothing);
      });
    });

    testWidgets('clearing doctor after going back updates step two', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Clear Doctor Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await completeStepOne(tester, patient: patient, searchQuery: 'Clear');

        final slotLabel = DateFormat.jm().format(DateTime(2026, 6, 27, 10));
        expect(find.text(slotLabel), findsOneWidget);
        expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);

        final backFinder = find.byKey(const Key('simplified_booking_back'));
        await tester.ensureVisible(backFinder);
        await tester.tap(backFinder);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(AppSelect<String>, 'Doctor (optional)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('No doctor assigned'));
        await tester.pumpAndSettle();

        final nextFinder = find.byKey(const Key('simplified_booking_step_one_next'));
        await tester.ensureVisible(nextFinder);
        await tester.tap(nextFinder);
        await tester.pump();
        await waitForStepTwo(tester);
        await tester.pumpAndSettle();

        expect(find.text(slotLabel), findsOneWidget);
        expect(client.rpcCallCounts['get_simplified_booking_slots'], 2);
        expect(find.text('Other doctors free'), findsNothing);
      });
    });

    testWidgets('completes two-step booking from step one through confirm', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Flow Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );

        await completeStepOne(tester, patient: patient, searchQuery: 'Flo');

        expect(find.text('Select Date and Time'), findsOneWidget);
        expect(find.text('Step 2 / 2'), findsOneWidget);

        final slotLabel = DateFormat.jm().format(DateTime(2026, 6, 27, 10));
        final slotFinder = find.text(slotLabel);
        await tester.ensureVisible(slotFinder);
        await tester.tap(slotFinder);
        await tester.pumpAndSettle();

        expect(find.text('Dr. Ada'), findsWidgets);

        final confirmFinder = find.byKey(const Key('simplified_slot_confirm'));
        await tester.ensureVisible(confirmFinder);
        await tester.tap(confirmFinder);
        await tester.pumpAndSettle();

        expect(client.createAppointmentCalls, hasLength(1));
        expect(client.createAppointmentCalls.single['p_patient_id'], patient.id);
        expect(client.createAppointmentCalls.single['p_doctor_id'], calendarTestDoctorAId);
        expect(client.createAppointmentCalls.single['p_duration_minutes'], 30);
      });
    });

    testWidgets('back from step two clears slot selection', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Back Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await completeStepOne(tester, patient: patient, searchQuery: 'Back');

        final slotLabel = DateFormat.jm().format(DateTime(2026, 6, 27, 10));
        final slotFinder = find.text(slotLabel);
        await tester.ensureVisible(slotFinder);
        await tester.tap(slotFinder);
        await tester.pumpAndSettle();
        expect(find.textContaining('Jun 27'), findsOneWidget);

        final backFinder = find.byKey(const Key('simplified_booking_back'));
        await tester.ensureVisible(backFinder);
        await tester.tap(backFinder);
        await tester.pumpAndSettle();

        expect(find.text('Step 1 / 2'), findsOneWidget);

        final nextFinder = find.byKey(const Key('simplified_booking_step_one_next'));
        await tester.ensureVisible(nextFinder);
        await tester.tap(nextFinder);
        await tester.pump();
        await waitForStepTwo(tester);
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();

        expect(find.text('Select a time slot above'), findsOneWidget);
        final confirm = tester.widget<AppButton>(find.byKey(const Key('simplified_slot_confirm')));
        expect(confirm.onPressed, isNull);
      });
    });

    testWidgets('next day chevron reloads slots without layout error', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Next Day Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await completeStepOne(tester, patient: patient, searchQuery: 'Next');
        expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);

        await tester.tap(find.byTooltip('Next day'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();

        expect(client.rpcCallCounts['get_simplified_booking_slots'], 2);
        expect(find.text('28'), findsWidgets);
      });
    });

    testWidgets('changing doctor in step one reloads step two grid', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 6, 27, 8, 0)), () async {
        final client = AppointmentRpcTestClient();
        final patient = samplePatientListItem(fullName: 'Doctor Change Patient');

        await pumpFlow(
          tester,
          client: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await completeStepOne(tester, patient: patient, searchQuery: 'Doc', doctorName: 'Dr. Ada');
        expect(client.rpcCallCounts['get_simplified_booking_slots'], 1);

        final backFinder = find.byKey(const Key('simplified_booking_back'));
        await tester.ensureVisible(backFinder);
        await tester.tap(backFinder);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(AppSelect<String>, 'Doctor (optional)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dr. Ben'));
        await tester.pumpAndSettle();

        final nextFinder = find.byKey(const Key('simplified_booking_step_one_next'));
        await tester.ensureVisible(nextFinder);
        await tester.tap(nextFinder);
        await tester.pump();
        await waitForStepTwo(tester);
        await waitForSlotsLoaded(tester);
        await tester.pumpAndSettle();

        expect(client.rpcCallCounts['get_simplified_booking_slots'], 2);
        expect(client.rpcLog.where((fn) => fn == 'get_simplified_booking_slots').last, 'get_simplified_booking_slots');
      });
    });
  });
}
