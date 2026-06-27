import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime_apply.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_start_doctor.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_session_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_stats_banner.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_waiting_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/queue_shift_doctor_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'appointment_queue_int_test_support.dart';

void main() {
  group('INT-001 — Realtime insert updates queue', () {
    test('insert event triggers refresh and appends new appointment without manual reload', () async {
      const existingId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      const insertedId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      final start = queueStartTimeToday(hour: 10);

      final rpcClient = QueueIntegrationRpcClient(
        todayItems: [queueRpcListItem(id: existingId, patientName: 'Existing Patient', startLocal: start)],
      );
      final realtimeClient = CapturingQueueRealtimeClient();
      final container = createQueueIntegrationContainer(rpcClient: rpcClient, realtimeClient: realtimeClient);
      addTearDown(container.dispose);

      await warmQueueProvider(container);
      final initialCalls = rpcClient.rpcCallCounts['list_appointments'] ?? 0;
      expect(container.read(appointmentQueueProvider).items, hasLength(1));

      rpcClient.todayItems = [
        ...rpcClient.todayItems,
        queueRpcListItem(
          id: insertedId,
          patientName: 'Inserted Patient',
          startLocal: start.add(const Duration(hours: 1)),
        ),
      ];

      realtimeClient.onAppointmentChange?.call(
        const AppointmentQueueRealtimeChange(eventType: PostgresChangeEvent.insert, newRecord: {'id': insertedId}),
      );
      await pumpEventQueue();
      await pumpEventQueue();

      final state = container.read(appointmentQueueProvider);
      expect(rpcClient.rpcCallCounts['list_appointments'], greaterThan(initialCalls));
      expect(state.items, hasLength(2));
      expect(state.items.map((item) => item.id), contains(insertedId));
      expect(state.items.lastWhere((item) => item.id == insertedId).patientName, 'Inserted Patient');
    });
  });

  group('INT-002 — Realtime status change patches row', () {
    test('checked-in realtime update patches queue row and waiting partition', () async {
      const appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final start = queueStartTimeToday(hour: 11);
      final checkedInAt = start.subtract(const Duration(minutes: 15));

      final rpcClient = QueueIntegrationRpcClient(
        todayItems: [
          queueRpcListItem(id: appointmentId, patientName: 'Calendar Patient', startLocal: start, status: 'confirmed'),
        ],
      );
      final realtimeClient = CapturingQueueRealtimeClient();
      final container = createQueueIntegrationContainer(rpcClient: rpcClient, realtimeClient: realtimeClient);
      addTearDown(container.dispose);

      await warmQueueProvider(container);
      final initialCalls = rpcClient.rpcCallCounts['list_appointments'] ?? 0;
      final before = container.read(appointmentQueueProvider).items.single;
      expect(before.status, AppointmentStatus.confirmed);
      expect(AppointmentQueueDisplay.partition([before]).waiting, isEmpty);

      realtimeClient.onAppointmentChange?.call(
        AppointmentQueueRealtimeChange(
          eventType: PostgresChangeEvent.update,
          newRecord: {
            'id': appointmentId,
            'start_time': start.toUtc().toIso8601String(),
            'end_time': start.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
            'status': 'checked_in',
            'type': 'planned',
            'updated_at': checkedInAt.toUtc().toIso8601String(),
            'checked_in_at': checkedInAt.toUtc().toIso8601String(),
          },
        ),
      );
      await pumpEventQueue();

      final state = container.read(appointmentQueueProvider);
      expect(rpcClient.rpcCallCounts['list_appointments'], initialCalls);
      final patched = state.items.singleWhere((item) => item.id == appointmentId);
      expect(patched.status, AppointmentStatus.checkedIn);
      expect(patched.checkedInAt, checkedInAt.toUtc());
      expect(AppointmentQueueDisplay.partition(state.items).waiting.single.id, appointmentId);
      expect(AppointmentQueueDisplay.partition(state.items).schedule.single.id, appointmentId);
    });

    testWidgets('checked-in realtime update reflects in waiting column UI', (tester) async {
      const appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final start = queueStartTimeToday(hour: 11);
      final checkedInAt = start.subtract(const Duration(minutes: 15));

      final rpcClient = QueueIntegrationRpcClient(
        todayItems: [
          queueRpcListItem(
            id: appointmentId,
            patientName: 'Checked In Patient',
            startLocal: start,
            status: 'confirmed',
          ),
        ],
      );
      final realtimeClient = CapturingQueueRealtimeClient();
      final overrides = queueIntegrationOverrides(rpcClient: rpcClient, realtimeClient: realtimeClient);

      await pumpQueuePage(tester, overrides: overrides);
      expect(find.text('Checked In Patient'), findsOneWidget);

      realtimeClient.onAppointmentChange?.call(
        AppointmentQueueRealtimeChange(
          eventType: PostgresChangeEvent.update,
          newRecord: {
            'id': appointmentId,
            'start_time': start.toUtc().toIso8601String(),
            'end_time': start.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
            'status': 'checked_in',
            'type': 'planned',
            'updated_at': checkedInAt.toUtc().toIso8601String(),
            'checked_in_at': checkedInAt.toUtc().toIso8601String(),
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.descendant(of: find.byType(AppointmentQueueWaitingColumn), matching: find.text('Checked in')),
        findsOneWidget,
      );
      expect(find.text('Checked In Patient'), findsNWidgets(2));
    });
  });

  group('INT-003 — Start assigns doctor then advances status', () {
    test('start flow assigns doctor via RPC then patches queue to in_progress', () async {
      const appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final start = queueStartTimeToday(hour: 10);
      final inProgressAt = start.add(const Duration(minutes: 5));

      final rpcClient = QueueIntegrationRpcClient(
        todayItems: [
          queueRpcListItem(
            id: appointmentId,
            patientName: 'Waiting Patient',
            startLocal: start,
            status: 'checked_in',
            checkedInAt: start.subtract(const Duration(minutes: 20)).toUtc().toIso8601String(),
          ),
        ],
      );
      final realtimeClient = CapturingQueueRealtimeClient();
      final container = createQueueIntegrationContainer(rpcClient: rpcClient, realtimeClient: realtimeClient);
      addTearDown(container.dispose);

      await warmQueueProvider(container);
      final repository = AppointmentRepository(rpcClient);
      final notifier = container.read(appointmentQueueProvider.notifier);

      await repository.updateAppointment(
        appointmentId: appointmentId,
        patientId: queuePatientAlphaId,
        doctorId: queueDoctorBetaId,
        startTime: start,
        endTime: start.add(const Duration(minutes: 30)),
      );
      final update = await repository.updateAppointmentStatus(
        appointmentId: appointmentId,
        newStatus: AppointmentStatus.inProgress,
      );

      notifier.patchAppointmentStatus(
        appointmentId: appointmentId,
        newStatus: AppointmentStatus.inProgress,
        doctorId: queueDoctorBetaId,
        doctorName: 'Dr Beta',
        updatedAt: update.updatedAt,
        inProgressAt: update.inProgressAt ?? inProgressAt,
      );

      expect(rpcClient.rpcCallCounts['update_appointment'], 1);
      expect(rpcClient.rpcCallCounts['update_appointment_status'], 1);
      expect(rpcClient.lastParams?['p_new_status'], 'in_progress');

      final patched = container.read(appointmentQueueProvider).items.single;
      expect(patched.status, AppointmentStatus.inProgress);
      expect(patched.doctorId, queueDoctorBetaId);
      expect(patched.doctorName, 'Dr Beta');
      expect(patched.inProgressAt, isNotNull);
      expect(AppointmentQueueDisplay.partition(container.read(appointmentQueueProvider).items).waiting, isEmpty);
    });

    testWidgets('doctor picker selection returns chosen doctor for start flow', (tester) async {
      final options = [
        QueueStartDoctorOption(id: queueDoctorAlphaId, name: 'Dr Alpha', isBusy: false),
        QueueStartDoctorOption(id: queueDoctorBetaId, name: 'Dr Beta', isBusy: false),
      ];

      String? selectedDoctorId;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: AppButton(
                  label: 'Open picker',
                  onPressed: () async {
                    selectedDoctorId = await QueueShiftDoctorPickerDialog.show(context, options: options);
                  },
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dr Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start visit'));
      await tester.pumpAndSettle();

      expect(selectedDoctorId, queueDoctorBetaId);
    });
  });

  group('INT-004 — Stats comparison previous working day', () {
    test('loads previous working day snapshot and computes day-over-day trends', () async {
      final now = queueStartTimeToday(hour: 12);
      final todayItems = [
        queueRpcListItem(
          id: 'today-completed',
          patientName: 'Today Completed',
          startLocal: now.subtract(const Duration(hours: 2)),
          status: 'completed',
        ),
        queueRpcListItem(
          id: 'today-waiting',
          patientName: 'Today Waiting',
          startLocal: now.add(const Duration(hours: 1)),
          status: 'checked_in',
          checkedInAt: now.subtract(const Duration(minutes: 30)).toUtc().toIso8601String(),
        ),
        queueRpcListItem(
          id: 'today-scheduled',
          patientName: 'Today Scheduled',
          startLocal: now.add(const Duration(hours: 2)),
        ),
      ];
      final comparisonItems = [
        queueRpcListItem(
          id: 'prev-completed',
          patientName: 'Previous Completed',
          startLocal: now.subtract(const Duration(days: 1, hours: 2)),
          status: 'completed',
        ),
        queueRpcListItem(
          id: 'prev-scheduled-1',
          patientName: 'Previous Scheduled 1',
          startLocal: now.subtract(const Duration(days: 1)),
        ),
        queueRpcListItem(
          id: 'prev-scheduled-2',
          patientName: 'Previous Scheduled 2',
          startLocal: now.subtract(const Duration(days: 1, hours: 1)),
        ),
      ];

      final rpcClient = QueueIntegrationRpcClient(todayItems: todayItems, comparisonItems: comparisonItems);
      final realtimeClient = CapturingQueueRealtimeClient();
      final container = createQueueIntegrationContainer(rpcClient: rpcClient, realtimeClient: realtimeClient);
      addTearDown(container.dispose);

      await warmQueueProvider(container);

      final state = container.read(appointmentQueueProvider);
      expect(state.comparisonUnavailable, isFalse);
      expect(state.comparisonItems, isNotNull);
      expect(state.comparisonItems, hasLength(3));
      expect(rpcClient.rpcCallCounts['list_appointments'], greaterThanOrEqualTo(2));

      final stats = AppointmentQueueDisplay.computeStats(
        state.items,
        now: DateTime.now(),
        comparisonItems: state.comparisonItems,
        comparisonNow: state.comparisonNow,
      );
      expect(stats.totalTrend?.percentChange, closeTo(0, 0.01));
      expect(stats.completedTrend?.percentChange, closeTo(0, 0.01));
      expect(stats.avgWaitTrend?.percentChange, closeTo(100, 0.01));
    });

    testWidgets('stat cards show trend percent from previous working day comparison', (tester) async {
      final now = queueStartTimeToday(hour: 12);
      final rpcClient = QueueIntegrationRpcClient(
        todayItems: [
          queueRpcListItem(id: 'today-ns-1', patientName: 'Today No Show 1', startLocal: now, status: 'no_show'),
          queueRpcListItem(
            id: 'today-ns-2',
            patientName: 'Today No Show 2',
            startLocal: now.add(const Duration(hours: 1)),
            status: 'no_show',
          ),
          queueRpcListItem(
            id: 'today-scheduled',
            patientName: 'Today Scheduled',
            startLocal: now.add(const Duration(hours: 2)),
          ),
        ],
        comparisonItems: [
          queueRpcListItem(
            id: 'prev-ns',
            patientName: 'Previous No Show',
            startLocal: now.subtract(const Duration(days: 1)),
            status: 'no_show',
          ),
          queueRpcListItem(
            id: 'prev-scheduled',
            patientName: 'Previous Scheduled',
            startLocal: now.subtract(const Duration(days: 1, hours: 1)),
          ),
        ],
      );
      final realtimeClient = CapturingQueueRealtimeClient();
      final overrides = queueIntegrationOverrides(rpcClient: rpcClient, realtimeClient: realtimeClient);

      await pumpQueuePage(tester, overrides: overrides);

      expect(
        find.descendant(of: find.byType(AppointmentQueueStatsBanner), matching: find.text('No-show')),
        findsOneWidget,
      );
      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('Day-over-day trends are temporarily unavailable.'), findsNothing);
    });
  });

  group('INT-005 — Shift doctors match today\'s shifts', () {
    test('shift lookup resolves the same doctors assigned on today\'s shift', () async {
      final realtimeClient = CapturingQueueRealtimeClient();
      final rpcClient = QueueIntegrationRpcClient(todayItems: const []);
      final container = createQueueIntegrationContainer(rpcClient: rpcClient, realtimeClient: realtimeClient);
      addTearDown(container.dispose);

      final lookup = await container.read(appointmentQueueShiftDoctorLookupProvider.future);
      final doctorsOnShift = lookup.doctorsOnCurrentShiftAt(DateTime.now());

      expect(doctorsOnShift.map((doctor) => doctor.name), ['Dr Alpha', 'Dr Beta']);
      expect(doctorsOnShift.map((doctor) => doctor.id), [queueDoctorAlphaId, queueDoctorBetaId]);
    });

    testWidgets('Doctors column lists shift doctors with accurate in-progress status', (tester) async {
      final start = queueStartTimeToday(hour: 10);
      final inProgressAt = start.add(const Duration(minutes: 8));

      final rpcClient = QueueIntegrationRpcClient(
        todayItems: [
          queueRpcListItem(
            id: 'in-progress-visit',
            patientName: 'In Progress Patient',
            startLocal: start,
            status: 'in_progress',
            doctorId: queueDoctorAlphaId,
            doctorName: 'Dr Alpha',
            inProgressAt: inProgressAt.toUtc().toIso8601String(),
          ),
        ],
      );
      final realtimeClient = CapturingQueueRealtimeClient();
      final overrides = queueIntegrationOverrides(rpcClient: rpcClient, realtimeClient: realtimeClient);

      await pumpQueuePage(tester, overrides: overrides);

      expect(find.text('Doctors'), findsOneWidget);
      expect(find.text('Dr Alpha'), findsWidgets);
      expect(find.text('Dr Beta'), findsOneWidget);

      final doctorsColumn = find.byType(AppointmentQueueSessionColumn);
      expect(find.descendant(of: doctorsColumn, matching: find.text('In Progress Patient')), findsOneWidget);
      expect(find.descendant(of: doctorsColumn, matching: find.text('No patient in progress')), findsOneWidget);
      expect(find.descendant(of: doctorsColumn, matching: find.text('Available')), findsOneWidget);
      expect(find.descendant(of: doctorsColumn, matching: find.textContaining('In session:')), findsOneWidget);
    });
  });
}
