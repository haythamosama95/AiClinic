import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_fetch_scope.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

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

void main() {
  group('AppointmentFetchScope', () {
    test('fromContext normalizes empty strings to null', () {
      const context = AuthSessionContext(
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

    test('patchAppointmentStatus updates a row without reloading', () async {
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
      notifier.patchAppointmentStatus(appointmentId: first.id, newStatus: AppointmentStatus.checkedIn);

      final updated = container.read(appointmentQueueProvider);
      expect(updated.loading, isFalse);
      expect(updated.items.firstWhere((item) => item.id == first.id).status, AppointmentStatus.checkedIn);
      expect(updated.items.firstWhere((item) => item.id == first.id).checkedInAt, isNotNull);
      expect(client.rpcCallCounts['list_appointments'], initialCalls);
    });
  });
}
