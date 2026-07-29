import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_shift_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_branch_staff.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/shift_rpc_test_client.dart';

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _ShiftStubRepository extends ShiftRepository {
  _ShiftStubRepository({
    required this.shifts,
    required this.branchStaff,
    ShiftRpcTestClient? client,
  }) : super(client ?? ShiftRpcTestClient());

  final List<ShiftListItem> shifts;
  final List<ShiftBranchStaffMember> branchStaff;

  @override
  Future<List<ShiftListItem>> listShifts({
    required String branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    bool includeCancelled = false,
  }) async => shifts;

  @override
  Future<List<ShiftBranchStaffMember>> listActiveStaffForBranch(String branchId) async => branchStaff;
}

class _StaffStubRepository implements StaffAdminRepository {
  _StaffStubRepository(this.staff);

  final List<StaffListItem> staff;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async => staff;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('appointmentDetailShiftLookupProvider', () {
    test('stupid usage: blank branch returns empty lookup', () async {
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
          shiftRepositoryProvider.overrideWithValue(
            _ShiftStubRepository(shifts: const [], branchStaff: const []),
          ),
        ],
      );
      addTearDown(container.dispose);

      final lookup = await container.read(
        appointmentDetailShiftLookupProvider(
          AppointmentDetailShiftQuery(
            branchId: '  ',
            appointmentStart: DateTime.utc(2026, 6, 4, 10),
          ),
        ).future,
      );

      expect(lookup, AppointmentQueueShiftDoctorLookup.empty);
    });

    test('trivial: fetches shifts and staff to build lookup', () async {
      const branchId = '44444444-4444-4444-8444-444444444444';
      final shifts = [
        ShiftListItem(
          id: 's1',
          branchId: branchId,
          shiftDate: DateTime(2026, 6, 4),
          startTime: '09:00',
          endTime: '17:00',
          status: ShiftStatus.active,
          isUnassigned: false,
          assigneeNames: const ['Dr Alpha'],
          assigneeCount: 1,
        ),
      ];
      final branchStaff = [
        const ShiftBranchStaffMember(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor),
      ];
      final fallbackStaff = [
        const StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
      ];

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
          shiftRepositoryProvider.overrideWithValue(
            _ShiftStubRepository(shifts: shifts, branchStaff: branchStaff),
          ),
          staffAdminRepositoryProvider.overrideWithValue(_StaffStubRepository(fallbackStaff)),
        ],
      );
      addTearDown(container.dispose);

      final lookup = await container.read(
        appointmentDetailShiftLookupProvider(
          AppointmentDetailShiftQuery(
            branchId: branchId,
            appointmentStart: DateTime.utc(2026, 6, 4, 10),
          ),
        ).future,
      );

      expect(lookup.doctorsOnShiftAt(DateTime.utc(2026, 6, 4, 10)), isNotEmpty);
    });

    test('invalid state: shift repository error propagates', () async {
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
          shiftRepositoryProvider.overrideWithValue(
            _FailingShiftRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final future = container.read(
        appointmentDetailShiftLookupProvider(
          AppointmentDetailShiftQuery(
            branchId: '44444444-4444-4444-8444-444444444444',
            appointmentStart: DateTime.utc(2026, 6, 4, 10),
          ),
        ).future,
      );

      await expectLater(future, throwsA(isA<RpcFailure>()));
    });
  });
}

class _FailingShiftRepository extends ShiftRepository {
  _FailingShiftRepository() : super(ShiftRpcTestClient());

  @override
  Future<List<ShiftListItem>> listShifts({
    required String branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    bool includeCancelled = false,
  }) {
    throw RpcFailure(
      const RpcResult(success: false, errorCode: 'FORBIDDEN', errorMessage: 'Denied'),
    );
  }
}
