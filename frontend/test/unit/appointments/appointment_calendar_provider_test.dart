import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

void main() {
  group('AppointmentCalendarController', () {
    late AppointmentRpcTestClient client;

    ProviderContainer createContainer(AuthSessionState authState) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(authState)),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        ],
      );
    }

    Future<AppointmentCalendarState> readAfterInit(ProviderContainer container) async {
      final _ = container.read(appointmentCalendarProvider);
      await pumpEventQueue();
      return container.read(appointmentCalendarProvider);
    }

    setUp(() {
      client = AppointmentRpcTestClient();
    });

    test('refresh loads appointments for active branch', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: '00000000-0000-4000-8000-000000000001',
          ),
        ),
      );
      addTearDown(container.dispose);

      final state = await readAfterInit(container);

      expect(state.loading, isFalse);
      expect(state.error, isNull);
      expect(state.items, hasLength(1));
      expect(client.rpcCallCounts['list_appointments'], 1);
    });

    test('refresh without branch shows selection error', () async {
      final container = createContainer(
        const AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: AuthSessionContext(
            staffProfile: StaffProfile(
              staffMemberId: '00000000-0000-4000-8000-000000000010',
              fullName: 'Test Staff',
              role: StaffRole.administrator,
              isBootstrapAdmin: false,
              isActive: true,
            ),
            organizationId: '00000000-0000-4000-8000-000000000020',
            branchIds: [],
            activeBranchId: null,
            permissions: {'appointments.read'},
            setupRequired: false,
          ),
        ),
      );
      addTearDown(container.dispose);

      final state = await readAfterInit(container);

      expect(state.items, isEmpty);
      expect(state.error, contains('active branch'));
    });

    test('setMode month requests month bounds', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: '00000000-0000-4000-8000-000000000001',
          ),
        ),
      );
      addTearDown(container.dispose);

      await readAfterInit(container);
      await container.read(appointmentCalendarProvider.notifier).setFocusDate(DateTime(2026, 6, 15));
      await container.read(appointmentCalendarProvider.notifier).setMode(AppointmentCalendarMode.month);
      await pumpEventQueue();

      final bounds = appointmentCalendarFetchBounds(DateTime(2026, 6, 15), AppointmentCalendarMode.month);
      final params = client.lastParams;
      expect(params, isNotNull);
      expect(params!['p_from'], bounds.$1.toIso8601String());
      expect(params['p_to'], bounds.$2.toIso8601String());
    });

    test('applyFilters updates branch and doctor then refreshes', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: '00000000-0000-4000-8000-000000000001',
          ),
        ),
      );
      addTearDown(container.dispose);

      await readAfterInit(container);
      await container
          .read(appointmentCalendarProvider.notifier)
          .applyFilters(
            branchId: '00000000-0000-4000-8000-000000000002',
            doctorId: '00000000-0000-4000-8000-000000000099',
          );
      await pumpEventQueue();

      final state = container.read(appointmentCalendarProvider);
      expect(state.selectedBranchId, '00000000-0000-4000-8000-000000000002');
      expect(state.selectedDoctorId, '00000000-0000-4000-8000-000000000099');
      expect(client.lastParams?['p_branch_id'], '00000000-0000-4000-8000-000000000002');
      expect(client.lastParams?['p_doctor_id'], '00000000-0000-4000-8000-000000000099');
    });

    test('clearFilters resets to active branch and clears doctor', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: '00000000-0000-4000-8000-000000000001',
          ),
        ),
      );
      addTearDown(container.dispose);

      await readAfterInit(container);
      await container
          .read(appointmentCalendarProvider.notifier)
          .applyFilters(
            branchId: '00000000-0000-4000-8000-000000000002',
            doctorId: '00000000-0000-4000-8000-000000000099',
          );
      await pumpEventQueue();

      await container.read(appointmentCalendarProvider.notifier).clearFilters();
      await pumpEventQueue();

      final state = container.read(appointmentCalendarProvider);
      expect(state.selectedBranchId, '00000000-0000-4000-8000-000000000001');
      expect(state.selectedDoctorId, isNull);
      expect(client.lastParams?['p_branch_id'], '00000000-0000-4000-8000-000000000001');
      expect(client.lastParams?.containsKey('p_doctor_id'), isFalse);
    });

    test('hasActiveFilters is false for initial branch-only state', () async {
      final container = createContainer(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: {'appointments.read'},
            activeBranchId: '00000000-0000-4000-8000-000000000001',
          ),
        ),
      );
      addTearDown(container.dispose);

      final state = await readAfterInit(container);

      expect(state.hasActiveFilters(initialBranchId: '00000000-0000-4000-8000-000000000001'), isFalse);
    });
  });
}
