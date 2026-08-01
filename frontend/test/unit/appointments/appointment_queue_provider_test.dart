import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/queue/data/queue_realtime.dart';
import 'package:ai_clinic/features/queue/data/queue_realtime_apply.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_fetch_scope.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/queue/presentation/providers/queue_provider.dart';
import 'package:ai_clinic/features/clinic-management/data/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
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
  AppointmentQueueRealtimeChangeCallback? onAppointmentChange;
  var unsubscribeCalls = 0;

  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {
    this.onAppointmentChange = onAppointmentChange;
    onSubscribe(onConnectionChanged);
  }

  @override
  void unsubscribe() {
    unsubscribeCalls += 1;
  }
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

class _RefreshFailAfterSuccessClient extends AppointmentRpcTestClient {
  var listCalls = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments') {
      listCalls += 1;
      if (listCalls >= 3) {
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

    test('BUG-007: shell warm provider loads queue data for nav badge', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [
            {
              ...appointmentRpcDefaultListItem(id: 'checked-in-1', startLocal: DateTime.utc(2026, 6, 4, 10)),
              'status': 'checked_in',
              'checked_in_at': '2026-06-04T09:30:00.000Z',
            },
          ],
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
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueShellWarmProvider);
      await pumpEventQueue();

      expect(client.rpcCallCounts['list_appointments'], greaterThanOrEqualTo(1));
      expect(container.read(appointmentQueueCheckedInCountProvider), 1);
    });

    test('build starts loading then refreshes and subscribes to realtime', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final realtimeClient = _CapturingAppointmentQueueRealtimeClient(onSubscribe: (_) {});
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(realtimeClient),
        ],
      );
      addTearDown(container.dispose);

      final initial = container.read(appointmentQueueProvider);
      expect(initial.loading, isTrue);
      expect(initial.items, isEmpty);

      await pumpEventQueue();

      final state = container.read(appointmentQueueProvider);
      expect(state.loading, isFalse);
      expect(state.items, isNotEmpty);
      expect(realtimeClient.onAppointmentChange, isNotNull);
    });

    test('refresh without branch sets selection error', () async {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {'appointments.read'},
                  branchIds: const [],
                  activeBranchId: null,
                ),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      final state = container.read(appointmentQueueProvider);
      expect(state.loading, isFalse);
      expect(state.items, isEmpty);
      expect(state.error, 'Select an active branch before viewing the queue.');
    });

    test('refresh with empty items sets loading true', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final slowClient = SlowAppointmentRpcTestClient(listDelay: const Duration(milliseconds: 50));
      slowClient.rpcResults['list_appointments'] = {
        'success': true,
        'data': {'items': <Map<String, dynamic>>[]},
      };

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(slowClient)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(appointmentQueueProvider.notifier);
      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      expect(container.read(appointmentQueueProvider).items, isEmpty);

      final refreshFuture = notifier.refresh();
      expect(container.read(appointmentQueueProvider).loading, isTrue);
      await refreshFuture;
      await pumpEventQueue();

      expect(container.read(appointmentQueueProvider).loading, isFalse);
    });

    test('refresh with existing items preserves items and skips loading flicker', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(appointmentQueueProvider.notifier);
      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      final existing = container.read(appointmentQueueProvider).items;
      expect(existing, isNotEmpty);

      await notifier.refresh();
      await pumpEventQueue();

      final state = container.read(appointmentQueueProvider);
      expect(state.loading, isFalse);
      expect(state.items, existing);
      expect(state.error, isNull);
    });

    test('refresh failure preserves existing items and sets error', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final failingClient = _RefreshFailAfterSuccessClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(failingClient)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(appointmentQueueProvider.notifier);
      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      final itemsBeforeFailure = container.read(appointmentQueueProvider).items;
      expect(itemsBeforeFailure, isNotEmpty);

      await notifier.refresh();
      await pumpEventQueue();

      final state = container.read(appointmentQueueProvider);
      expect(state.items, itemsBeforeFailure);
      expect(state.error, 'Unable to load today\'s queue. Try again.');
    });

    test('realtime connection updates are ignored after unsubscribe', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      AppointmentQueueRealtimeStatusCallback? onConnectionChanged;
      final realtimeClient = _CapturingAppointmentQueueRealtimeClient(
        onSubscribe: (callback) => onConnectionChanged = callback,
      );

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(realtimeClient),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      container.dispose();
      onConnectionChanged?.call(AppointmentQueueRealtimeConnection.degraded);
      await pumpEventQueue();
    });

    test('patchAppointmentStatus with unknown id is a no-op', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(appointmentQueueProvider.notifier);
      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      final before = container.read(appointmentQueueProvider).items;
      notifier.patchAppointmentStatus(appointmentId: 'missing-id', newStatus: AppointmentStatus.checkedIn);

      expect(container.read(appointmentQueueProvider).items, before);
    });

    test('patchAppointmentStatus replaces known row and re-sorts', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [
            appointmentRpcDefaultListItem(id: 'later', startLocal: DateTime.utc(2026, 6, 4, 12)),
            appointmentRpcDefaultListItem(id: 'earlier', startLocal: DateTime.utc(2026, 6, 4, 9)),
          ],
        },
      };

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(appointmentQueueProvider.notifier);
      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      notifier.patchAppointmentStatus(
        appointmentId: 'later',
        newStatus: AppointmentStatus.checkedIn,
        updatedAt: DateTime.utc(2026, 6, 4, 8),
      );

      final items = container.read(appointmentQueueProvider).items;
      expect(items.first.id, 'earlier');
      expect(items.last.status, AppointmentStatus.checkedIn);
    });

    test('realtime change applies in place when payload is sufficient', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final today = DateTime.now().toUtc();
      final updatedStart = DateTime.utc(today.year, today.month, today.day, 11);
      final updatedEnd = updatedStart.add(const Duration(minutes: 30));
      final realtimeClient = _CapturingAppointmentQueueRealtimeClient(onSubscribe: (_) {});
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(realtimeClient),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();
      final callsBefore = client.rpcCallCounts['list_appointments'] ?? 0;
      final targetId = container.read(appointmentQueueProvider).items.first.id;

      realtimeClient.onAppointmentChange?.call(
        AppointmentQueueRealtimeChange(
          eventType: PostgresChangeEvent.update,
          newRecord: {
            'id': targetId,
            'start_time': updatedStart.toIso8601String(),
            'end_time': updatedEnd.toIso8601String(),
            'status': 'confirmed',
            'type': 'planned',
          },
        ),
      );
      await pumpEventQueue();

      expect(container.read(appointmentQueueProvider).items.first.status, AppointmentStatus.confirmed);
      expect(client.rpcCallCounts['list_appointments'], callsBefore);
    });

    test('realtime insert falls back to full refresh', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final realtimeClient = _CapturingAppointmentQueueRealtimeClient(onSubscribe: (_) {});
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(realtimeClient),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();
      final callsBefore = client.rpcCallCounts['list_appointments'] ?? 0;

      realtimeClient.onAppointmentChange?.call(
        const AppointmentQueueRealtimeChange(eventType: PostgresChangeEvent.insert, newRecord: {'id': 'new'}),
      );
      await pumpEventQueue();

      expect(client.rpcCallCounts['list_appointments'], greaterThan(callsBefore));
    });

    test('comparison items are null when previous working day cannot be resolved', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final closedSchedule = BranchWorkingSchedule([
        for (final day in BranchWeekday.values) BranchWorkingDayHours(day: day, isWorkingDay: false),
      ]);

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(_FakeAppointmentQueueRealtimeClient()),
          branchRepositoryProvider.overrideWithValue(
            _ClosedBranchRepository(branchId: branchId, schedule: closedSchedule),
          ),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      final state = container.read(appointmentQueueProvider);
      expect(state.comparisonItems, isNull);
      expect(state.comparisonUnavailable, isFalse);
    });

    test('realtime unsubscribe runs on dispose', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final realtimeClient = _CapturingAppointmentQueueRealtimeClient(onSubscribe: (_) {});
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _MutableAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}, activeBranchId: branchId),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          appointmentQueueRealtimeClientProvider.overrideWithValue(realtimeClient),
        ],
      );

      final _ = container.read(appointmentQueueProvider);
      await pumpEventQueue();
      container.dispose();

      expect(realtimeClient.unsubscribeCalls, greaterThanOrEqualTo(1));
    });
  });
}

class _ClosedBranchRepository implements BranchRepository {
  _ClosedBranchRepository({required this.branchId, required this.schedule});

  final String branchId;
  final BranchWorkingSchedule schedule;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    return [BranchListItem(id: branchId, name: 'Closed Branch', code: 'CB', isActive: true, workingSchedule: schedule)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
