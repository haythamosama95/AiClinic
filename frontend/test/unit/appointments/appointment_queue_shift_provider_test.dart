import 'package:ai_clinic/app/providers/auth_session_provider.dart';
<<<<<<< HEAD
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
=======
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';
import 'package:ai_clinic/features/queue/presentation/providers/queue_shift_provider.dart';
>>>>>>> master
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

class _QueueShiftStubRepository extends ShiftRepository {
  _QueueShiftStubRepository({
    required this.shifts,
    required this.branchStaff,
  }) : super(ShiftRpcTestClient());

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

ShiftListItem _shift({required List<String> assignees}) {
  return ShiftListItem(
    id: 's1',
    branchId: 'b1',
    shiftDate: DateTime(2026, 6, 4),
    startTime: '09:00',
    endTime: '17:00',
    status: ShiftStatus.active,
    isUnassigned: false,
    assigneeNames: assignees,
    assigneeCount: assignees.length,
  );
}

void main() {
  group('resolveQueueShiftDoctors', () {
    const branchDoctor = ShiftBranchStaffMember(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor);
    const branchNurse = ShiftBranchStaffMember(id: 'n1', fullName: 'Nurse One', role: StaffRole.receptionist);
    const fallbackDoctor = StaffListItem(id: 'd2', fullName: 'Dr Beta', role: StaffRole.doctor, isActive: true);
    const inactiveDoctor = StaffListItem(id: 'd3', fullName: 'Dr Gamma', role: StaffRole.doctor, isActive: false);

    test('trivial: branch doctors are added to the map', () {
      final doctors = resolveQueueShiftDoctors(
        branchStaff: const [branchDoctor, branchNurse],
        shifts: const [],
        fallbackStaff: const [],
      );

      expect(doctors.map((doctor) => doctor.id), ['d1']);
    });

    test('advanced: shift assignees match branch staff by name', () {
      final doctors = resolveQueueShiftDoctors(
        branchStaff: const [branchDoctor],
        shifts: [_shift(assignees: const ['Dr Alpha'])],
        fallbackStaff: const [fallbackDoctor],
      );

      expect(doctors.map((doctor) => doctor.id), ['d1']);
    });

    test('advanced: shift assignees fall back to org staff when branch match missing', () {
      final doctors = resolveQueueShiftDoctors(
        branchStaff: const [],
        shifts: [_shift(assignees: const ['Dr Beta'])],
        fallbackStaff: const [fallbackDoctor],
      );

      expect(doctors.map((doctor) => doctor.id), ['d2']);
    });

    test('edge case: no assignee keys returns all branch doctors', () {
      final doctors = resolveQueueShiftDoctors(
        branchStaff: const [branchDoctor, branchNurse],
        shifts: [_shift(assignees: const [])],
        fallbackStaff: const [fallbackDoctor],
      );

      expect(doctors.map((doctor) => doctor.id), ['d1']);
    });

    test('edge case: empty resolved set falls back to all active org doctors', () {
      final doctors = resolveQueueShiftDoctors(
        branchStaff: const [branchNurse],
        shifts: const [],
        fallbackStaff: const [fallbackDoctor, inactiveDoctor],
      );

      expect(doctors.map((doctor) => doctor.id), ['d2']);
    });

    test('edge case: ambiguous duplicate branch doctor names both match assignee keys', () {
      final doctors = resolveQueueShiftDoctors(
        branchStaff: const [
          ShiftBranchStaffMember(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor),
          ShiftBranchStaffMember(id: 'd4', fullName: 'Dr Alpha', role: StaffRole.doctor),
        ],
        shifts: [_shift(assignees: const ['Dr Alpha'])],
        fallbackStaff: const [],
      );

      expect(doctors.map((doctor) => doctor.id).toSet(), {'d1', 'd4'});
    });

    test('advanced: non-doctor staff are excluded from results', () {
      final doctors = resolveQueueShiftDoctors(
        branchStaff: const [branchNurse],
        shifts: [_shift(assignees: const ['Nurse One'])],
        fallbackStaff: const [],
      );

      expect(doctors, isEmpty);
    });
  });

  group('appointmentQueueShiftDoctorLookupProvider', () {
    test('stupid usage: blank branch returns empty lookup', () async {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {'appointments.read'},
                  activeBranchId: '   ',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final lookup = await container.read(appointmentQueueShiftDoctorLookupProvider.future);

      expect(lookup, AppointmentQueueShiftDoctorLookup.empty);
    });

    test('trivial: fetches today shifts for active branch', () async {
      const branchId = '44444444-4444-4444-8444-444444444444';
      final shifts = [_shift(assignees: const ['Dr Alpha'])];
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  permissions: {'appointments.read'},
                  activeBranchId: branchId,
                ),
              ),
            ),
          ),
          shiftRepositoryProvider.overrideWithValue(
            _QueueShiftStubRepository(
              shifts: shifts,
              branchStaff: const [
                ShiftBranchStaffMember(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor),
              ],
            ),
          ),
          staffAdminRepositoryProvider.overrideWithValue(
            _StaffStubRepository(const [
              StaffListItem(id: 'd1', fullName: 'Dr Alpha', role: StaffRole.doctor, isActive: true),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final lookup = await container.read(appointmentQueueShiftDoctorLookupProvider.future);

      expect(lookup, isNot(AppointmentQueueShiftDoctorLookup.empty));
    });
  });
}
