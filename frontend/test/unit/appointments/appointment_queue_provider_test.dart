import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime_apply.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

void main() {
  setUpAll(ensureAppointmentTimezonesInitialized);

  group('AppointmentQueueController', () {
    late AppointmentRpcTestClient client;
    late _RecordingRealtime realtime;

    const branchId = '44444444-4444-4444-8444-444444444444';

    ProviderContainer container({AuthSessionState? auth}) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuth(
              auth ??
                  AuthSessionState(
                    status: AuthSessionStatus.authenticated,
                    context: sampleAuthSessionContext(activeBranchId: branchId, branchIds: [branchId]),
                  ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(realtime),
        ],
      );
    }

    setUp(() {
      client = AppointmentRpcTestClient();
      realtime = _RecordingRealtime();
    });

    test('trivial: loads today appointments sorted by start_time', () async {
      final range = appointmentTodayRangeInTimezone('UTC', DateTime.now().toUtc());
      final morning = range.from.add(const Duration(hours: 9));
      final afternoon = range.from.add(const Duration(hours: 14));

      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [_row('b', afternoon), _row('a', morning)],
        },
      };

      final ref = container();
      addTearDown(ref.dispose);
      ref.read(appointmentQueueProvider);
      await _pumpAsync();

      final state = ref.read(appointmentQueueProvider);

      expect(state.loading, isFalse);
      expect(state.items, hasLength(2));
      expect(state.items.first.id, 'a');
      expect(state.items.last.id, 'b');
      expect(client.lastFunction, 'list_appointments');
    });

    test('advanced: sends today bounds to list_appointments', () async {
      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {'items': []},
      };

      final ref = container();
      addTearDown(ref.dispose);
      ref.read(appointmentQueueProvider);
      await _pumpAsync();

      final from = DateTime.parse(client.lastParams!['p_from'] as String);
      final to = DateTime.parse(client.lastParams!['p_to'] as String);
      expect(to.difference(from), const Duration(days: 1));
    });

    test('invalid state: missing active branch shows guidance error', () async {
      final ref = container(
        auth: const AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: AuthSessionContext(
            staffProfile: StaffProfile(
              staffMemberId: 's',
              fullName: 'Staff',
              role: StaffRole.receptionist,
              isBootstrapAdmin: false,
              isActive: true,
            ),
            organizationId: 'org',
            branchIds: [],
            activeBranchId: null,
            permissions: {},
            setupRequired: false,
          ),
        ),
      );
      addTearDown(ref.dispose);
      ref.read(appointmentQueueProvider);
      await _pumpAsync();

      final state = ref.read(appointmentQueueProvider);

      expect(state.error, contains('active branch'));
      expect(state.items, isEmpty);
      expect(client.lastFunction, isNull);
    });

    test('edge case: filters out appointments outside today range', () async {
      final range = appointmentTodayRangeInTimezone('UTC', DateTime.now().toUtc());
      final today = range.from.add(const Duration(hours: 10));
      final tomorrow = range.to.add(const Duration(hours: 1));

      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [_row('today', today), _row('tomorrow', tomorrow)],
        },
      };

      final ref = container();
      addTearDown(ref.dispose);
      ref.read(appointmentQueueProvider);
      await _pumpAsync();

      final state = ref.read(appointmentQueueProvider);

      expect(state.items, hasLength(1));
      expect(state.items.single.id, 'today');
    });

    test('stupid user: RPC failure surfaces retry message', () async {
      client.rpcResults['list_appointments'] = {'success': false, 'error_code': 'FORBIDDEN', 'error_message': 'Nope'};

      final ref = container();
      addTearDown(ref.dispose);
      ref.read(appointmentQueueProvider);
      await _pumpAsync();

      final state = ref.read(appointmentQueueProvider);

      expect(state.error, contains('Could not load'));
      expect(state.items, isEmpty);
    });

    test('regression: realtime update patches queue without immediate refresh', () async {
      final range = appointmentTodayRangeInTimezone('UTC', DateTime.now().toUtc());
      final start = range.from.add(const Duration(hours: 10));

      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [_row('a1', start)],
        },
      };

      final ref = container();
      addTearDown(ref.dispose);

      ref.read(appointmentQueueProvider.notifier);
      await _pumpAsync();
      expect(ref.read(appointmentQueueProvider).items.single.id, 'a1');
      final listCallsAfterInit = client.rpcCallCounts['list_appointments'] ?? 0;

      realtime.triggerChange(
        AppointmentQueueRealtimeChange(
          eventType: PostgresChangeEvent.update,
          newRecord: {
            'id': 'a1',
            'start_time': start.add(const Duration(hours: 1)).toIso8601String(),
            'end_time': start.add(const Duration(hours: 1, minutes: 30)).toIso8601String(),
            'status': 'confirmed',
            'type': 'planned',
          },
        ),
      );

      final updated = ref.read(appointmentQueueProvider).items.single;
      expect(updated.status, AppointmentStatus.confirmed);
      expect(client.rpcCallCounts['list_appointments'], listCallsAfterInit);
    });

    test('regression: realtime insert schedules debounced refresh', () async {
      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {'items': []},
      };

      final ref = container();
      addTearDown(ref.dispose);

      ref.read(appointmentQueueProvider.notifier);
      await _pumpAsync();
      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [_row('new', DateTime.now().toUtc())],
        },
      };

      realtime.triggerChange(
        const AppointmentQueueRealtimeChange(eventType: PostgresChangeEvent.insert, newRecord: {'id': 'new'}),
      );

      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(client.lastFunction, 'list_appointments');
    });

    test('regression: realtime change triggers refresh when payload insufficient', () async {
      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {'items': []},
      };

      final ref = container();
      addTearDown(ref.dispose);

      ref.read(appointmentQueueProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(realtime.lastBranchId, branchId);

      realtime.triggerChange(
        const AppointmentQueueRealtimeChange(eventType: PostgresChangeEvent.insert, newRecord: {'id': 'missing-names'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(client.lastFunction, 'list_appointments');
    });

    test('degraded: realtime subscribe failure marks degraded state', () async {
      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {'items': []},
      };
      realtime.initialConnection = AppointmentQueueRealtimeConnection.degraded;

      final ref = container();
      addTearDown(ref.dispose);

      ref.read(appointmentQueueProvider);
      await _pumpAsync();

      expect(ref.read(appointmentQueueProvider).isDegraded, isTrue);
    });
  });
}

Future<void> _pumpAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Map<String, dynamic> _row(String id, DateTime start) {
  final end = start.add(const Duration(minutes: 20));
  return {
    'id': id,
    'patient_id': 'p',
    'patient_name': 'Patient $id',
    'doctor_id': 'd',
    'doctor_name': 'Dr',
    'start_time': start.toIso8601String(),
    'end_time': end.toIso8601String(),
    'type': 'planned',
    'status': 'scheduled',
  };
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);
  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

class _RecordingRealtime implements AppointmentQueueRealtimeClient {
  String? lastBranchId;
  AppointmentQueueRealtimeChangeCallback? onChange;
  AppointmentQueueRealtimeConnection initialConnection = AppointmentQueueRealtimeConnection.live;

  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {
    lastBranchId = branchId;
    onChange = onAppointmentChange;
    onConnectionChanged(initialConnection);
  }

  void triggerChange(AppointmentQueueRealtimeChange change) => onChange?.call(change);

  @override
  void unsubscribe() {
    lastBranchId = null;
    onChange = null;
  }
}
