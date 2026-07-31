import 'package:ai_clinic/app/application/clinic_data_changed_provider.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_surface_invalidation.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/data/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/appointment_calendar_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import '../../support/shift_rpc_test_client.dart';

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _CountingAppointmentRpcClient extends AppointmentRpcTestClient {
  _CountingAppointmentRpcClient(this.onRpc);

  final void Function(String fn) onRpc;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    onRpc(fn);
    return super.rpc(fn, params: params, get: get);
  }
}

void main() {
  group('invalidateAppointmentSurfaceProviders', () {
    test('advanced: invalidates queue, calendar, shift lookup, branches, and doctors providers', () async {
      var rpcCount = 0;
      final client = _CountingAppointmentRpcClient((_) => rpcCount += 1);
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {'appointments.read'},
                  activeBranchId: calendarTestBranchAId,
                ),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
          branchRepositoryProvider.overrideWithValue(CalendarStubBranchRepository()),
          staffAdminRepositoryProvider.overrideWithValue(CalendarDoctorsStubStaffRepository()),
          shiftRepositoryProvider.overrideWithValue(ShiftRepository(ShiftRpcTestClient())),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueProvider);
      final __ = container.read(appointmentCalendarProvider);
      final ___ = container.read(appointmentQueueShiftDoctorLookupProvider);
      final ____ = container.read(appointmentCalendarBranchesProvider);
      final _____ = container.read(appointmentCalendarDoctorsProvider);
      await pumpEventQueue();
      final countBefore = rpcCount;

      invalidateAppointmentSurfaceProviders(container.read);
      await pumpEventQueue();

      final ______ = container.read(appointmentQueueProvider);
      final _______ = container.read(appointmentCalendarProvider);
      await pumpEventQueue();

      expect(rpcCount, greaterThan(countBefore));
    });
  });

  group('invalidateAppointmentAfterVisitCompleted', () {
    test('advanced: invalidates detail family plus calendar and queue providers', () async {
      const appointmentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      var detailCalls = 0;
      final client = _CountingAppointmentRpcClient((fn) {
        if (fn == 'get_appointment') {
          detailCalls += 1;
        }
      });

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(permissions: {'appointments.read'}),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(appointmentDetailProvider(appointmentId).future);
      final detailCallsBefore = detailCalls;

      invalidateAppointmentAfterVisitCompleted(container.read, appointmentId: appointmentId);
      await container.read(appointmentDetailProvider(appointmentId).future);

      expect(detailCalls, greaterThan(detailCallsBefore));
    });
  });

  group('appointmentQueueShellWarmProvider', () {
    test('advanced: clinic data bump invalidates appointment surfaces', () async {
      var rpcCount = 0;
      final client = _CountingAppointmentRpcClient((_) => rpcCount += 1);
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {'appointments.read'},
                  activeBranchId: calendarTestBranchAId,
                ),
              ),
            ),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client)),
        ],
      );
      addTearDown(container.dispose);

      final _ = container.read(appointmentQueueShellWarmProvider);
      await pumpEventQueue();
      final countBefore = rpcCount;

      container.read(clinicDataChangedProvider.notifier).bump();
      await pumpEventQueue();

      final __ = container.read(appointmentQueueProvider);
      await pumpEventQueue();

      expect(rpcCount, greaterThan(countBefore));
    });
  });
}
