import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../helpers/appointment_queue_test_support.dart' show tapWaitingColumnPatient;
import 'appointment_queue_abuse_test_support.dart';

void main() {
  group('ABUSE-001 — Double tap Start in journey dialog', () {
    testWidgets('single status RPC and busy state block duplicate Start', (tester) async {
      final listItems = [
        queueListRpcItem(
          id: queueCheckedInAppointmentId,
          patientName: 'Checked In Patient',
          doctorId: queueDoctorAId,
          doctorName: 'Dr. Ada',
        ),
      ];
      final client = QueueScenarioRpcClient(
        listItems: listItems,
        statusUpdateDelay: const Duration(milliseconds: 500),
      );

      await pumpAppointmentQueueRoutes(tester, client: client);
      final container = await waitForQueueLoaded(tester);

      await openQueueJourneyDialog(tester, queueCheckedInAppointmentId);
      await waitForJourneyDetailLoaded(tester);

      await tester.tap(queueAdvanceButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Confirm doctor'), findsOneWidget);

      await tester.tap(find.text('Start visit'));
      await tester.tap(find.text('Start visit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(client.rpcCallCounts['update_appointment_status'], lessThanOrEqualTo(1));

      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(client.rpcCallCounts['update_appointment_status'], 1);

      final inProgressCount = container
          .read(appointmentQueueProvider)
          .items
          .where((item) => item.status == AppointmentStatus.inProgress)
          .length;
      expect(inProgressCount, lessThanOrEqualTo(1));
    });
  });

  group('ABUSE-002 — Rapid open/close journey dialog', () {
    testWidgets('no exception when opening and closing dialog quickly on multiple rows', (tester) async {
      final listItems = [
        queueListRpcItem(
          id: queueCheckedInAppointmentId,
          patientName: 'Patient Alpha',
          doctorId: queueDoctorAId,
          doctorName: 'Dr. Ada',
        ),
        queueListRpcItem(
          id: queueSecondAppointmentId,
          patientName: 'Patient Beta',
          doctorId: queueDoctorAId,
          doctorName: 'Dr. Ada',
          startUtc: queueTodayStartUtc(hour: 11),
        ),
      ];
      final client = QueueScenarioRpcClient(listItems: listItems);

      await pumpAppointmentQueueRoutes(tester, client: client);
      await waitForQueueLoaded(tester);

      for (final appointmentId in [queueCheckedInAppointmentId, queueSecondAppointmentId, queueCheckedInAppointmentId]) {
        await openQueueJourneyDialog(tester, appointmentId);
        await closeQueueJourneyDialog(tester);
        await tester.pump(const Duration(milliseconds: 30));
      }

      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AppointmentQueuePage), findsOneWidget);
    });
  });

  group('ABUSE-003 — Navigate away during status RPC', () {
    testWidgets('RPC completes safely and queue refreshes on return', (tester) async {
      final listItems = [
        queueListRpcItem(
          id: queueScheduledAppointmentId,
          patientName: 'Scheduled Patient',
          status: 'scheduled',
          doctorId: queueDoctorAId,
          doctorName: 'Dr. Ada',
        ),
      ];
      final client = QueueScenarioRpcClient(
        listItems: listItems,
        statusUpdateDelay: const Duration(milliseconds: 600),
      );

      await pumpAppointmentQueueRoutes(tester, client: client);
      final container = await waitForQueueLoaded(tester);
      final initialListCalls = client.rpcCallCounts['list_appointments'] ?? 0;

      await openQueueJourneyDialog(tester, queueScheduledAppointmentId);
      await waitForJourneyDetailLoaded(tester);

      await tester.tap(queueAdvanceButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await navigateToQueueCalendar(tester);
      await tester.pump(const Duration(milliseconds: 700));

      expect(tester.takeException(), isNull);
      expect(find.byType(AppointmentCalendarPage), findsOneWidget);
      expect(client.rpcCallCounts['update_appointment_status'], 1);

      await navigateToQueuePage(tester);
      await waitForQueueLoaded(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AppointmentQueuePage), findsOneWidget);
      expect(client.rpcCallCounts['list_appointments'], greaterThan(initialListCalls));
      expect(container.read(appointmentQueueProvider).error, isNull);
    });
  });

  group('ABUSE-004 — Resize window during scroll animation', () {
    testWidgets('layout settles without exception when crossing wide breakpoint during flash', (tester) async {
      final listItems = [
        queueListRpcItem(
          id: queueCheckedInAppointmentId,
          patientName: 'Waiting Patient',
          doctorId: queueDoctorAId,
          doctorName: 'Dr. Ada',
        ),
        queueListRpcItem(
          id: queueSecondAppointmentId,
          patientName: 'Schedule Anchor',
          status: 'scheduled',
          doctorId: queueDoctorAId,
          doctorName: 'Dr. Ada',
          startUtc: queueTodayStartUtc(hour: 14),
        ),
      ];
      final client = QueueScenarioRpcClient(listItems: listItems);

      await pumpAppointmentQueueRoutes(tester, client: client, surfaceSize: queueWideSurfaceSize);
      await waitForQueueLoaded(tester);

      await tapWaitingColumnPatient(tester, 'Waiting Patient');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.binding.setSurfaceSize(queueNarrowSurfaceSize);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.binding.setSurfaceSize(queueWideSurfaceSize);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(tester.takeException(), isNull);
      expect(find.byType(AppointmentQueuePage), findsOneWidget);

      final scrollables = tester.widgetList<Scrollable>(find.byType(Scrollable)).length;
      expect(scrollables, lessThan(12));
    });
  });

  group('ABUSE-005 — Dismiss doctor picker', () {
    testWidgets('escape and back leave status unchanged with no doctor assign RPC', (tester) async {
      final listItems = [
        queueListRpcItem(
          id: queueCheckedInAppointmentId,
          patientName: 'Unassigned Patient',
        ),
      ];
      final client = QueueScenarioRpcClient(listItems: listItems);

      await pumpAppointmentQueueRoutes(
        tester,
        client: client,
        shiftLookup: queueMultiDoctorShiftLookup(),
      );
      final container = await waitForQueueLoaded(tester);

      await openQueueJourneyDialog(tester, queueCheckedInAppointmentId);
      await waitForJourneyDetailLoaded(tester);

      await tester.tap(queueAdvanceButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Confirm doctor'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final dynamic widgetsBinding = tester.binding;
      await widgetsBinding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(client.rpcCallCounts['update_appointment'], isNull);
      expect(client.rpcCallCounts['update_appointment_status'], isNull);

      final item = container.read(appointmentQueueProvider).items.firstWhere((row) => row.id == queueCheckedInAppointmentId);
      expect(item.status, AppointmentStatus.checkedIn);
      expect(tester.takeException(), isNull);
    });
  });

  group('ABUSE-006 — Spam Retry on load error', () {
    testWidgets('repeated Retry does not duplicate realtime subscriptions', (tester) async {
      final client = AlwaysFailingQueueListRpcClient();
      final realtime = CountingQueueRealtimeClient();

      await pumpAppointmentQueueRoutes(tester, client: client, realtimeClient: realtime);
      await waitForQueueLoaded(tester);

      expect(find.text('Retry'), findsOneWidget);
      final subscribeAfterInitialLoad = realtime.subscribeCount;

      for (var i = 0; i < 8; i++) {
        await tester.tap(find.text('Retry'));
        await tester.pump(const Duration(milliseconds: 20));
      }

      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(realtime.subscribeCount, subscribeAfterInitialLoad);
      expect(realtime.unsubscribeCount, lessThanOrEqualTo(realtime.subscribeCount));
      expect(client.rpcCallCounts['list_appointments'], greaterThanOrEqualTo(2));
      expect(find.textContaining('Unable to load today'), findsOneWidget);
    });
  });
}
