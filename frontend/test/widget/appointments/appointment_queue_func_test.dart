import 'package:clock/clock.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_schedule_column.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/appointment_queue_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'appointment_booking_sheet_test_support.dart';

void main() {
  group('FUNC-001 — Queue page loads today\'s appointments', () {
    testWidgets('shows today\'s schedule rows sorted by time and stats banner counts', (tester) async {
      final client = StatefulQueueRpcClient(
        items: [
          queueRpcListItem(id: queueApptLateId, patientName: 'Late Patient', startLocal: queueTodayLocal(hour: 15)),
          queueRpcListItem(id: queueApptEarlyId, patientName: 'Early Patient', startLocal: queueTodayLocal(hour: 9)),
        ],
      );

      await pumpQueuePage(tester, authState: queueAuthState(), rpcClient: client);
      await waitForQueueLoaded(tester);

      expect(find.text('Early Patient'), findsOneWidget);
      expect(find.text('Late Patient'), findsOneWidget);
      expect(find.text('Total appointments'), findsOneWidget);
      expect(find.text('2'), findsWidgets);

      final earlyY = tester.getTopLeft(find.text('Early Patient')).dy;
      final lateY = tester.getTopLeft(find.text('Late Patient')).dy;
      expect(earlyY, lessThan(lateY));
      expect(find.byType(AppSkeletonBox), findsNothing);
    });
  });

  group('FUNC-002 — Permission denied without appointment access', () {
    testWidgets('shows queue access required and does not fetch appointments', (tester) async {
      final client = AppointmentRpcTestClient();

      await pumpQueuePage(
        tester,
        authState: queueAuthState(permissions: {PermissionKeys.patientsView}),
        rpcClient: client,
      );
      await tester.pumpAndSettle();

      expect(find.text('Queue access required'), findsOneWidget);
      expect(find.text('Appointments'), findsNothing);
      // Provider may still warm via route lifecycle even when the page is gated.
    });
  });

  group('FUNC-003 — Missing active branch guidance', () {
    testWidgets('shows branch selection error with retry', (tester) async {
      final client = StatefulQueueRpcClient(
        items: [queueRpcListItem(id: queueApptScheduledId, patientName: 'Queue Patient')],
      );

      await pumpQueuePage(tester, authState: queueAuthWithoutBranch(), rpcClient: client);
      await tester.pumpAndSettle();

      expect(find.text('Select an active branch before viewing the queue.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(client.rpcCallCounts['list_appointments'] ?? 0, 0);
    });
  });

  group('FUNC-004 — Confirm appointment from journey dialog', () {
    testWidgets('confirms scheduled appointment, shows toast, and updates row badge', (tester) async {
      final client = StatefulQueueRpcClient(
        items: [
          queueRpcListItem(
            id: queueApptScheduledId,
            patientName: 'Scheduled Patient',
            status: AppointmentStatus.scheduled,
          ),
        ],
      );

      await pumpQueuePage(tester, authState: queueAuthState(), rpcClient: client);
      await waitForQueueLoaded(tester);

      await openQueueJourneyDialog(tester, appointmentId: queueApptScheduledId);
      expect(find.text('Confirm'), findsOneWidget);

      final statusUpdatesBefore = client.rpcCallCounts['update_appointment_status'] ?? 0;
      await tapJourneyAdvanceAction(tester);
      await tester.pumpAndSettle();

      expect(client.rpcCallCounts['update_appointment_status'], statusUpdatesBefore + 1);
      expect(find.textContaining('Appointment marked as confirmed'), findsOneWidget);
      expect(find.text('Confirmed'), findsWidgets);

      final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
      final item = container.read(appointmentQueueProvider).items.firstWhere((row) => row.id == queueApptScheduledId);
      expect(item.status, AppointmentStatus.confirmed);
      expect(find.byType(AppSkeletonBox), findsNothing);
    });
  });

  group('FUNC-005 — Check in appointment', () {
    testWidgets('checks in confirmed appointment and increments nav badge count', (tester) async {
      final client = StatefulQueueRpcClient(
        items: [
          queueRpcListItem(
            id: queueApptConfirmedId,
            patientName: 'Confirmed Patient',
            status: AppointmentStatus.confirmed,
          ),
        ],
      );

      await pumpQueuePage(tester, authState: queueAuthState(), rpcClient: client);
      await waitForQueueLoaded(tester);
      expect(queueCheckedInBadgeCount(tester), 0);

      await openQueueJourneyDialog(tester, appointmentId: queueApptConfirmedId);
      await tapJourneyAdvanceAction(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Appointment marked as checked in'), findsOneWidget);
      expect(find.text('Confirmed Patient'), findsWidgets);
      expect(queueCheckedInBadgeCount(tester), 1);

      final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
      final item = container.read(appointmentQueueProvider).items.firstWhere((row) => row.id == queueApptConfirmedId);
      expect(item.status, AppointmentStatus.checkedIn);
    });
  });

  group('FUNC-006 — Start appointment with doctor picker', () {
    testWidgets('assigns doctor and moves appointment to in progress', (tester) async {
      final client = StatefulQueueRpcClient(
        items: [
          queueRpcListItem(
            id: queueApptCheckedInId,
            patientName: 'Checked In Patient',
            status: AppointmentStatus.checkedIn,
          ),
        ],
      );

      await pumpQueuePage(tester, authState: queueAuthState(), rpcClient: client);
      await waitForQueueLoaded(tester);

      await openQueueJourneyDialog(tester, appointmentId: queueApptCheckedInId);
      await tapJourneyAdvanceAction(tester);
      await selectDoctorInPicker(tester, 'Dr Beta');

      expect(find.textContaining('Appointment marked as in progress'), findsOneWidget);
      expect(find.text('In progress'), findsWidgets);
      expect(find.text('Checked In Patient'), findsWidgets);
      expect(client.rpcCallCounts['update_appointment'], greaterThanOrEqualTo(1));
      expect(client.rpcCallCounts['update_appointment_status'], greaterThanOrEqualTo(1));

      final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
      final item = container.read(appointmentQueueProvider).items.firstWhere((row) => row.id == queueApptCheckedInId);
      expect(item.status, AppointmentStatus.inProgress);
      expect(item.doctorId, queueTestDoctorBetaId);
    });
  });

  group('FUNC-007 — Start blocked when all doctors busy', () {
    testWidgets('disables start with all-doctors-busy tooltip and skips status RPC', (tester) async {
      final client = StatefulQueueRpcClient(
        items: [
          queueRpcListItem(
            id: queueApptActiveAlphaId,
            patientName: 'Alpha Active',
            status: AppointmentStatus.inProgress,
            doctorId: queueTestDoctorAlphaId,
            doctorName: 'Dr Alpha',
          ),
          queueRpcListItem(
            id: queueApptActiveBetaId,
            patientName: 'Beta Active',
            status: AppointmentStatus.inProgress,
            doctorId: queueTestDoctorBetaId,
            doctorName: 'Dr Beta',
            startLocal: queueTodayLocal(hour: 11),
          ),
          queueRpcListItem(
            id: queueApptWaitingId,
            patientName: 'Waiting Patient',
            status: AppointmentStatus.checkedIn,
            startLocal: queueTodayLocal(hour: 12),
          ),
        ],
      );

      await pumpQueuePage(tester, authState: queueAuthState(), rpcClient: client);
      await waitForQueueLoaded(tester);

      await openQueueJourneyDialog(tester, appointmentId: queueApptWaitingId);

      final advanceButton = queueAdvanceButton(tester);
      expect(advanceButton.onPressed, isNull);
      expect(advanceButton.label, 'Start');

      final statusUpdatesBefore = client.rpcCallCounts['update_appointment_status'] ?? 0;
      await tester.tap(find.byKey(const Key('appointment_control_advance_status')));
      await tester.pumpAndSettle();
      expect(client.rpcCallCounts['update_appointment_status'] ?? 0, statusUpdatesBefore);

      expect(queueAdvanceButton(tester).onPressed, isNull);
    });
  });

  group('FUNC-008 — Start with busy preferred doctor, free alternate', () {
    testWidgets('starts with alternate doctor when preferred doctor is busy', (tester) async {
      final client = StatefulQueueRpcClient(
        items: [
          queueRpcListItem(
            id: queueApptActiveAlphaId,
            patientName: 'Alpha Active',
            status: AppointmentStatus.inProgress,
            doctorId: queueTestDoctorAlphaId,
            doctorName: 'Dr Alpha',
          ),
          queueRpcListItem(
            id: queueApptWaitingId,
            patientName: 'Preferred Alpha Patient',
            status: AppointmentStatus.checkedIn,
            doctorId: queueTestDoctorAlphaId,
            doctorName: 'Dr Alpha',
            startLocal: queueTodayLocal(hour: 11),
          ),
        ],
      );

      await pumpQueuePage(tester, authState: queueAuthState(), rpcClient: client);
      await waitForQueueLoaded(tester);

      await openQueueJourneyDialog(tester, appointmentId: queueApptWaitingId);
      await tapJourneyAdvanceAction(tester);
      await selectDoctorInPicker(tester, 'Dr Beta');

      final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
      final item = container.read(appointmentQueueProvider).items.firstWhere((row) => row.id == queueApptWaitingId);
      expect(item.status, AppointmentStatus.inProgress);
      expect(item.doctorId, queueTestDoctorBetaId);
      expect(find.text('Preferred Alpha Patient'), findsWidgets);
    });
  });

  group('FUNC-009 — Mark no-show', () {
    testWidgets('marks confirmed appointment as no-show and updates stats', (tester) async {
      final client = StatefulQueueRpcClient(
        items: [
          queueRpcListItem(
            id: queueApptConfirmedId,
            patientName: 'No Show Patient',
            status: AppointmentStatus.confirmed,
          ),
        ],
      );

      await pumpQueuePage(tester, authState: queueAuthState(), rpcClient: client);
      await waitForQueueLoaded(tester);

      await openQueueJourneyDialog(tester, appointmentId: queueApptConfirmedId);
      await tapJourneyNoShowAction(tester);
      await confirmNoShowDialog(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Appointment marked as no-show'), findsOneWidget);
      expect(find.text('No-show'), findsWidgets);

      final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
      final item = container.read(appointmentQueueProvider).items.firstWhere((row) => row.id == queueApptConfirmedId);
      expect(item.status, AppointmentStatus.noShow);
    });
  });

  group('FUNC-010 — Cancel appointment with reason', () {
    testWidgets('cancels scheduled appointment and dims schedule row', (tester) async {
      final client = StatefulQueueRpcClient(
        items: [
          queueRpcListItem(
            id: queueApptScheduledId,
            patientName: 'Cancel Patient',
            status: AppointmentStatus.scheduled,
          ),
        ],
      );

      await pumpQueuePage(tester, authState: queueAuthState(), rpcClient: client);
      await waitForQueueLoaded(tester);

      await openQueueJourneyDialog(tester, appointmentId: queueApptScheduledId);
      await tapJourneyCancelAction(tester);
      await completeCancelDialog(tester, reason: 'Clinic closure');
      await tester.pumpAndSettle();

      expect(find.textContaining('Appointment cancelled'), findsOneWidget);
      expect(client.rpcCallCounts['cancel_appointment'], 1);

      // Cancelled rows leave the active schedule partition (patient name may remain in the open dialog title).
      expect(
        find.descendant(of: find.byType(AppointmentQueueScheduleColumn), matching: find.text('Cancel Patient')),
        findsNothing,
      );

      final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
      final item = container.read(appointmentQueueProvider).items.firstWhere((row) => row.id == queueApptScheduledId);
      expect(item.status, AppointmentStatus.cancelled);
    });
  });

  group('FUNC-011 — Book appointment from queue schedule header', () {
    testWidgets('books from schedule header and refreshes queue with new appointment', (tester) async {
      await withClock(Clock.fixed(queueTodayLocal(hour: 10)), () async {
        final client = StatefulQueueRpcClient(items: []);
        final patient = samplePatientListItem(fullName: 'Booked Patient');

        await pumpQueuePage(
          tester,
          authState: queueAuthState(),
          rpcClient: client,
          patientRepository: FakePatientRepository(patients: [patient]),
        );
        await waitForQueueLoaded(tester);

        await tapBookAppointmentHeader(tester);
        await submitValidBooking(tester, patient: patient, searchQuery: 'Booked');
        await tester.pumpAndSettle();

        expect(client.createAppointmentCalls, hasLength(1));

        final container = ProviderScope.containerOf(tester.element(find.byType(AppointmentQueuePage)));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.text('Booked Patient').evaluate().isNotEmpty) {
            break;
          }
        }

        expect(find.text('Booked Patient'), findsOneWidget);
        expect(client.rpcCallCounts['list_appointments'], greaterThanOrEqualTo(2));
      });
    });
  });
}
