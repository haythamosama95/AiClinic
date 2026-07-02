import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_schedule_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_session_column.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_stats_banner.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/appointment_queue_waiting_column.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/appointment_queue_test_support.dart';
import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/fake_postgrest_rpc.dart';
import '../../widget/appointments/appointment_calendar_test_support.dart';

class _MutableAuthSessionNotifier extends TestAuthSessionNotifier {
  _MutableAuthSessionNotifier(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

class _FailListAppointmentsRpcClient extends AppointmentRpcTestClient {
  var failListAppointments = false;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments' && failListAppointments) {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      return FakePostgrestRpc({'success': false, 'error_code': 'NETWORK', 'error_message': 'offline'})
          as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _StaticQueueNotifier extends AppointmentQueueController {
  _StaticQueueNotifier(this.initialState);

  final AppointmentQueueState initialState;
  var refreshCalls = 0;

  @override
  AppointmentQueueState build() => initialState;

  @override
  Future<void> refresh() async {
    refreshCalls += 1;
  }
}

AuthSessionState _queueAuthState({String organizationTimezone = 'UTC'}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: {PermissionKeys.appointmentsRead},
      activeBranchId: '00000000-0000-4000-8000-000000000001',
    ).copyWith(organizationTimezone: organizationTimezone),
  );
}

Future<void> _pumpQueueWidget(WidgetTester tester, {required Widget child, List<Override> overrides = const []}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(_queueAuthState())),
        appointmentCalendarBranchesProvider.overrideWith((ref) async => const []),
        ...appointmentQueueTestOverrides(),
        ...overrides,
      ],
      child: ForuiAppScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _scheduleTimeRangeLabel(DateTime start, DateTime end) {
  final format = DateFormat('h:mm a');
  return '${format.format(start.toLocal())} - ${format.format(end.toLocal())}';
}

AppointmentListItem _item({
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? startTime,
  DateTime? endTime,
  DateTime? checkedInAt,
  String? doctorId,
  String? doctorName,
  String id = 'a1',
  String patientName = 'Pat',
}) {
  final start = startTime ?? DateTime.utc(2026, 6, 4, 10);
  return AppointmentListItem(
    id: id,
    patientId: 'p1',
    patientName: patientName,
    doctorId: doctorId,
    doctorName: doctorName,
    startTime: start,
    endTime: endTime ?? start.add(const Duration(minutes: 30)),
    type: AppointmentType.planned,
    status: status,
    checkedInAt: checkedInAt,
  );
}

void main() {
  setUpAll(ensureAppointmentTimezonesInitialized);

  group('EDGE-001 — Empty queue today', () {
    test('partition and stats reflect an empty today queue', () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final partition = AppointmentQueueDisplay.partition(const [], now: now);
      final stats = AppointmentQueueDisplay.computeStats(const [], now: now);

      expect(partition.schedule, isEmpty);
      expect(partition.waiting, isEmpty);
      expect(stats.total, 0);
      expect(stats.completed, 0);
      expect(stats.noShow, 0);
      expect(stats.avgWaitMinutes, isNull);
      expect(stats.avgVisitMinutes, isNull);
    });

    testWidgets('schedule, checked-in, and doctors columns show empty states', (tester) async {
      final now = DateTime.utc(2026, 6, 4, 12);
      final shiftLookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [
          ShiftListItem(
            id: 's1',
            branchId: 'b1',
            shiftDate: DateTime(2026, 6, 4),
            startTime: '09:00',
            endTime: '17:00',
            status: ShiftStatus.active,
            isUnassigned: false,
            assigneeNames: const ['Dr Alpha'],
            assigneeCount: 1,
          ),
        ],
        doctors: const [StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true)],
      );

      await _pumpQueueWidget(
        tester,
        child: Column(
          children: [
            AppointmentQueueStatsBanner(stats: AppointmentQueueDisplay.computeStats(const [], now: now)),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: AppointmentQueueScheduleColumn(items: const [], now: now, bodyScrollable: false),
                  ),
                  Expanded(
                    child: AppointmentQueueWaitingColumn(items: const [], now: now, bodyScrollable: false),
                  ),
                  Expanded(
                    child: AppointmentQueueSessionColumn(
                      appointments: const [],
                      now: now,
                      shiftLookup: shiftLookup,
                      bodyScrollable: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No appointments today'), findsOneWidget);
      expect(find.text('No patients checked in'), findsOneWidget);
      expect(find.text('Dr Alpha'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3));
      expect(find.text('—'), findsNWidgets(2));
    });
  });

  group('EDGE-002 — Wait tier warning at 15 minutes', () {
    test('waitTierFor uses warning at 15 minutes and critical at 30 minutes', () {
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 14)), AppointmentQueueWaitTier.normal);
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 15)), AppointmentQueueWaitTier.warning);
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 16)), AppointmentQueueWaitTier.warning);
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 29)), AppointmentQueueWaitTier.warning);
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 30)), AppointmentQueueWaitTier.critical);
      expect(AppointmentQueueDisplay.waitTierFor(const Duration(minutes: 45)), AppointmentQueueWaitTier.critical);
    });

    test('waitPresentation reports warning tier for a 16-minute checked-in wait', () {
      final now = DateTime.utc(2026, 6, 4, 10, 16);
      final checkedInAt = now.subtract(const Duration(minutes: 16));
      final item = _item(status: AppointmentStatus.checkedIn, checkedInAt: checkedInAt);

      final (_, tier) = AppointmentQueueDisplay.waitPresentation(item, now: now);

      expect(tier, AppointmentQueueWaitTier.warning);
    });

    test('waitPresentation reports critical tier for a 30-minute checked-in wait', () {
      final now = DateTime.utc(2026, 6, 4, 10, 30);
      final checkedInAt = now.subtract(const Duration(minutes: 30));
      final item = _item(status: AppointmentStatus.checkedIn, checkedInAt: checkedInAt);

      final (_, tier) = AppointmentQueueDisplay.waitPresentation(item, now: now);

      expect(tier, AppointmentQueueWaitTier.critical);
    });
  });

  group('EDGE-003 — Appointment without preferred doctor on shift', () {
    final shiftDoctors = const [
      StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
      StaffListItem(id: 'd2', fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true),
    ];

    final morningShift = ShiftListItem(
      id: 's1',
      branchId: 'b1',
      shiftDate: DateTime(2026, 6, 4),
      startTime: '09:00',
      endTime: '13:00',
      status: ShiftStatus.active,
      isUnassigned: false,
      assigneeNames: const ['Dr Alpha', 'Dr Beta'],
      assigneeCount: 2,
    );

    test('queueDoctorPresentation keeps assigned doctor name when doctor is not on shift', () {
      final lookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [morningShift],
        doctors: shiftDoctors,
      );
      final offShiftDoctor = _item(doctorId: 'd9', doctorName: 'Dr Gamma', startTime: DateTime.utc(2026, 6, 4, 10));

      final presentation = AppointmentQueueDisplay.queueDoctorPresentation(offShiftDoctor, shiftLookup: lookup);

      expect(presentation.displayNames, 'Dr Gamma');
      expect(presentation.hasPatientChoice, isTrue);
      expect(AppointmentQueueDisplay.queueDoctorLabel(offShiftDoctor, shiftLookup: lookup), 'Dr Gamma');
      expect(lookup.doctorsOnShiftAt(offShiftDoctor.startTime).map((d) => d.name), ['Dr Alpha', 'Dr Beta']);
    });

    test('queueDoctorPresentation shows no preferred doctor when appointment is unassigned', () {
      final lookup = AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors(
        organizationTimezone: 'UTC',
        shifts: [morningShift],
        doctors: shiftDoctors,
      );
      final unassigned = _item(doctorId: null, doctorName: null, startTime: DateTime.utc(2026, 6, 4, 10));

      final presentation = AppointmentQueueDisplay.queueDoctorPresentation(unassigned, shiftLookup: lookup);

      expect(presentation.displayNames, AppointmentQueueDisplay.noPreferredDoctorLabel);
      expect(presentation.hasPatientChoice, isFalse);
    });
  });

  group('EDGE-004 — Timezone boundary near midnight', () {
    const timezone = 'Africa/Nairobi';

    test('appointmentTodayRangeInTimezone keeps late-evening appointments in today', () {
      final referenceUtc = DateTime.utc(2026, 6, 4, 20, 30);
      final range = appointmentTodayRangeInTimezone(timezone, referenceUtc);
      final lateSameDay = DateTime.utc(2026, 6, 4, 20, 45);

      expect(appointmentStartTimeIsWithinRange(lateSameDay, range), isTrue);
    });

    test('appointmentTodayRangeInTimezone excludes appointments just after local midnight', () {
      final referenceUtc = DateTime.utc(2026, 6, 4, 20, 30);
      final range = appointmentTodayRangeInTimezone(timezone, referenceUtc);
      final justAfterMidnight = DateTime.utc(2026, 6, 4, 21, 15);

      expect(appointmentStartTimeIsWithinRange(justAfterMidnight, range), isFalse);
    });

    test('appointmentTodayRangeInTimezone uses org calendar day rather than UTC day', () {
      final referenceUtc = DateTime.utc(2026, 6, 4, 20, 30);
      final orgRange = appointmentTodayRangeInTimezone(timezone, referenceUtc);
      final utcRange = appointmentTodayRangeInTimezone('UTC', referenceUtc);

      expect(orgRange.from, DateTime.utc(2026, 6, 3, 21));
      expect(orgRange.to, DateTime.utc(2026, 6, 4, 21));
      expect(utcRange.from, DateTime.utc(2026, 6, 4));
      expect(orgRange, isNot(equals(utcRange)));
    });
  });

  group('EDGE-005 — Completed row shows time range', () {
    test('isScheduleRowDimmed marks completed appointments as dimmed', () {
      final completed = _item(status: AppointmentStatus.completed);
      final scheduled = _item(status: AppointmentStatus.scheduled, id: 'a2');

      expect(AppointmentQueueDisplay.isScheduleRowDimmed(completed), isTrue);
      expect(AppointmentQueueDisplay.isScheduleRowDimmed(scheduled), isFalse);
    });

    testWidgets('schedule column shows start-end range for completed rows', (tester) async {
      final start = DateTime.utc(2026, 6, 4, 10);
      final end = start.add(const Duration(minutes: 30));
      final completed = _item(
        id: 'completed',
        status: AppointmentStatus.completed,
        startTime: start,
        endTime: end,
        patientName: 'Completed Pat',
      );
      final scheduled = _item(
        id: 'scheduled',
        status: AppointmentStatus.scheduled,
        startTime: start.add(const Duration(hours: 1)),
        patientName: 'Scheduled Pat',
      );
      final now = DateTime.utc(2026, 6, 4, 12);

      await _pumpQueueWidget(
        tester,
        child: AppointmentQueueScheduleColumn(items: [completed, scheduled], now: now, bodyScrollable: false),
      );
      await tester.pumpAndSettle();

      expect(find.text(_scheduleTimeRangeLabel(start, end)), findsOneWidget);
      expect(find.text(DateFormat('h:mm a').format(scheduled.startTime.toLocal())), findsOneWidget);
      expect(find.textContaining(' - '), findsOneWidget);

      final opacityFinder = find.byWidgetPredicate((widget) => widget is Opacity && widget.opacity == 0.5);
      expect(opacityFinder, findsOneWidget);
    });
  });

  group('EDGE-006 — RPC failure shows retry on load', () {
    test('refresh preserves existing items when list_appointments fails', () async {
      final client = _FailListAppointmentsRpcClient();
      final authNotifier = _MutableAuthSessionNotifier(_queueAuthState());

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => authNotifier),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(appointmentQueueProvider.notifier);
      await notifier.refresh();
      await pumpEventQueue();

      final loaded = container.read(appointmentQueueProvider);
      expect(loaded.items, isNotEmpty);
      expect(loaded.error, isNull);

      client.failListAppointments = true;
      await notifier.refresh();
      await pumpEventQueue();

      final failed = container.read(appointmentQueueProvider);
      expect(failed.error, 'Unable to load today\'s queue. Try again.');
      expect(failed.items, loaded.items);
      expect(failed.loading, isFalse);
    });

    testWidgets('queue page shows error text and retry while keeping loaded content', (tester) async {
      final existing = _item(id: 'kept', patientName: 'Kept Patient');
      final notifier = _StaticQueueNotifier(
        AppointmentQueueState(items: [existing], error: 'Unable to load today\'s queue. Try again.', loading: false),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(() => PresetAuthSessionNotifier(_queueAuthState())),
            appointmentQueueRealtimeClientProvider.overrideWithValue(FakeAppointmentQueueRealtimeClient()),
            appointmentQueueProvider.overrideWith(() => notifier),
          ],
          child: ForuiAppScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(appointmentQueueProvider);
                    final controller = ref.read(appointmentQueueProvider.notifier);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.error != null) ...[
                          Text(state.error!),
                          AppButton(label: 'Retry', variant: AppButtonVariant.secondary, onPressed: controller.refresh),
                        ],
                        for (final item in state.items) Text(item.patientName),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Unable to load today\'s queue. Try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Kept Patient'), findsOneWidget);

      final callsBeforeRetry = notifier.refreshCalls;
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(notifier.refreshCalls, callsBeforeRetry + 1);
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
