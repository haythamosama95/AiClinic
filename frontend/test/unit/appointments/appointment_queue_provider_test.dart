import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_fetch_scope.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/fake_postgrest_rpc.dart';

class _MutableAuthSessionNotifier extends TestAuthSessionNotifier {
  _MutableAuthSessionNotifier(this._state);

  AuthSessionState _state;

  @override
  AuthSessionState build() => _state;

  void replace(AuthSessionState next) {
    _state = next;
    state = next;
  }
}

class _FakeAppointmentQueueRealtimeClient implements AppointmentQueueRealtimeClient {
  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {}

  @override
  void unsubscribe() {}
}

class _CapturingAppointmentQueueRealtimeClient implements AppointmentQueueRealtimeClient {
  _CapturingAppointmentQueueRealtimeClient({required this.onSubscribe});

  final void Function(AppointmentQueueRealtimeStatusCallback callback) onSubscribe;

  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {
    onSubscribe(onConnectionChanged);
  }

  @override
  void unsubscribe() {}
}

class _ComparisonFailRpcClient extends AppointmentRpcTestClient {
  var listCalls = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments') {
      listCalls += 1;
      if (listCalls > 1) {
        rpcLog.add(fn);
        lastFunction = fn;
        lastParams = params == null ? null : Map<String, dynamic>.from(params);
        rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
        return FakePostgrestRpc({'success': false, 'error_code': 'NETWORK', 'error_message': 'offline'})
            as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc(fn, params: params, get: get);
  }
}

void main() {
  group('AppointmentFetchScope', () {
    test('fromContext normalizes empty strings to null', () {
      final context = AuthSessionContext(
        staffProfile: StaffProfile(
          staffMemberId: 'staff-1',
          fullName: 'Staff',
          role: StaffRole.administrator,
          isBootstrapAdmin: false,
          isActive: true,
        ),
        organizationId: '  ',
        branchIds: ['branch-1'],
        activeBranchId: ' branch-1 ',
        permissions: {},
        setupRequired: false,
        organizationTimezone: '',
      );

      expect(AppointmentFetchScope.fromContext(context), const AppointmentFetchScope(activeBranchId: 'branch-1'));
    });
  });

  group('AppointmentQueueController', () {
    late AppointmentRpcTestClient client;

    setUp(() {
      client = AppointmentRpcTestClient();
    });

    test('refresh runs again when organization changes but branch stays the same', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final authNotifier = _MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: branchId,
          ).copyWith(organizationId: '00000000-0000-4000-8000-000000000010', organizationTimezone: 'UTC'),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => authNotifier),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();
      expect(client.rpcCallCounts['list_appointments'], 2);

      authNotifier.replace(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: branchId,
          ).copyWith(organizationId: '00000000-0000-4000-8000-000000000099', organizationTimezone: 'Africa/Cairo'),
        ),
      );
      await pumpEventQueue();

      expect(client.rpcCallCounts['list_appointments'], 4);
    });

    test('patchAppointmentStatus uses server timestamps when provided', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final authNotifier = _MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: branchId,
          ).copyWith(organizationId: '00000000-0000-4000-8000-000000000010', organizationTimezone: 'UTC'),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => authNotifier),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(appointmentQueueProvider.notifier);
      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      final initialCalls = client.rpcCallCounts['list_appointments'] ?? 0;
      final queueState = container.read(appointmentQueueProvider);
      expect(queueState.items, isNotEmpty);
      expect(queueState.loading, isFalse);

      final first = queueState.items.first;
      final serverCheckedInAt = DateTime.utc(2026, 6, 4, 9, 45);
      notifier.patchAppointmentStatus(
        appointmentId: first.id,
        newStatus: AppointmentStatus.checkedIn,
        checkedInAt: serverCheckedInAt,
        updatedAt: DateTime.utc(2026, 6, 4, 10),
      );

      final updated = container.read(appointmentQueueProvider);
      expect(updated.loading, isFalse);
      final patched = updated.items.firstWhere((item) => item.id == first.id);
      expect(patched.status, AppointmentStatus.checkedIn);
      expect(patched.checkedInAt, serverCheckedInAt);
      expect(client.rpcCallCounts['list_appointments'], initialCalls);
    });

    test('BUG-001: patchAppointmentStatus does not invent client checkedInAt', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final authNotifier = _MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: branchId,
          ).copyWith(organizationId: '00000000-0000-4000-8000-000000000010', organizationTimezone: 'UTC'),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => authNotifier),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(appointmentQueueProvider.notifier);
      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      final first = container.read(appointmentQueueProvider).items.first;
      notifier.patchAppointmentStatus(appointmentId: first.id, newStatus: AppointmentStatus.checkedIn);

      final patched = container.read(appointmentQueueProvider).items.firstWhere((item) => item.id == first.id);
      expect(patched.checkedInAt, isNull);
    });

    test('BUG-002: surfaces degraded realtime connection in state', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      AppointmentQueueRealtimeStatusCallback? onConnectionChanged;

      final realtimeClient = _CapturingAppointmentQueueRealtimeClient(
        onSubscribe: (callback) => onConnectionChanged = callback,
      );

      final authNotifier = _MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: branchId,
          ).copyWith(organizationId: '00000000-0000-4000-8000-000000000010', organizationTimezone: 'UTC'),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => authNotifier),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(realtimeClient),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      onConnectionChanged?.call(AppointmentQueueRealtimeConnection.degraded);
      await pumpEventQueue();

      expect(container.read(appointmentQueueProvider).realtimeConnection, AppointmentQueueRealtimeConnection.degraded);
    });

    test('BUG-006: marks comparison unavailable when previous-day fetch fails', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final failingClient = _ComparisonFailRpcClient();
      failingClient.rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [appointmentRpcDefaultListItem()],
        },
      };

      final authNotifier = _MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: branchId,
          ).copyWith(organizationId: '00000000-0000-4000-8000-000000000010', organizationTimezone: 'UTC'),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => authNotifier),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(failingClient)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      final state = container.read(appointmentQueueProvider);
      expect(state.comparisonUnavailable, isTrue);
      expect(state.comparisonItems, isNull);
    });
  });
}
