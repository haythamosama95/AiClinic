import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/presentation/dev/appointment_dev_seed_service.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentDevSeedService', () {
    const branchId = '44444444-4444-4444-8444-444444444444';
    const organizationId = '33333333-3333-4333-8333-333333333333';

    late AppointmentRpcTestClient rpcClient;
    late AppointmentDevSeedService service;
    late FakePatientRepository patients;
    late FakeStaffAdminRepository staffAdmin;
    late _FakeBranchRepository branches;

    setUp(() {
      rpcClient = AppointmentRpcTestClient();
      patients = FakePatientRepository(patients: [samplePatientListItem(branchId: branchId)]);
      staffAdmin = FakeStaffAdminRepository(
        staff: [const StaffListItem(id: 'doc-1', fullName: 'Dr One', role: StaffRole.doctor, isActive: true)],
      );
      branches = _FakeBranchRepository(branchId: branchId, workingSchedule: BranchWorkingSchedule.defaultSchedule());
      service = AppointmentDevSeedService(
        appointments: AppointmentRepository(rpcClient),
        searchPatients: SearchPatients(patients),
        listStaff: ListStaff(staffAdmin),
        branches: branches,
      );
    });

    test('creates planned and walk-in appointments within working hours', () async {
      final outcome = await service.seed(
        branchId: branchId,
        organizationId: organizationId,
        referenceNow: DateTime(2026, 5, 28, 10, 0),
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.plannedCreated, appointmentDevSeedPlannedCount);
      expect(outcome.walkInCreated, appointmentDevSeedWalkInCount);
      expect(rpcClient.createAppointmentCalls, hasLength(10));

      final plannedCalls = rpcClient.createAppointmentCalls.where((p) => p['p_type'] == 'planned').toList();
      expect(plannedCalls, hasLength(appointmentDevSeedPlannedCount));
      for (final params in plannedCalls) {
        expect(params.containsKey('p_start_time'), isTrue);
        expect(params['p_doctor_id'], isNotNull);
        final start = DateTime.parse(params['p_start_time'] as String).toLocal();
        expect(start.hour * 60 + start.minute + 30, lessThanOrEqualTo(17 * 60));
      }
    });

    test('sends null p_doctor_id when no doctors are available', () async {
      staffAdmin.staff = [];

      final outcome = await service.seed(
        branchId: branchId,
        organizationId: organizationId,
        referenceNow: DateTime(2026, 5, 28, 10, 0),
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.plannedCreated, appointmentDevSeedPlannedCount);
      expect(outcome.walkInCreated, 0);
      for (final params in rpcClient.createAppointmentCalls) {
        expect(params['p_doctor_id'], isNull);
      }
    });

    test('loads postgres-style working schedule from branch list', () async {
      branches.workingSchedule = BranchWorkingSchedule.fromJson({
        'days': [
          {'day': 'sunday', 'is_working_day': false},
          {'day': 'monday', 'is_working_day': true, 'open_time': '09:00:00', 'close_time': '17:00:00'},
          {'day': 'tuesday', 'is_working_day': true, 'open_time': '09:00:00', 'close_time': '17:00:00'},
          {'day': 'wednesday', 'is_working_day': true, 'open_time': '09:00:00', 'close_time': '17:00:00'},
          {'day': 'thursday', 'is_working_day': true, 'open_time': '09:00:00', 'close_time': '17:00:00'},
          {'day': 'friday', 'is_working_day': true, 'open_time': '09:00:00', 'close_time': '17:00:00'},
          {'day': 'saturday', 'is_working_day': true, 'open_time': '09:00:00', 'close_time': '17:00:00'},
        ],
      })!;

      final outcome = await service.seed(
        branchId: branchId,
        organizationId: organizationId,
        referenceNow: DateTime(2026, 5, 31, 10, 0),
      );

      expect(outcome.isSuccess, isTrue);
      final firstPlanned = rpcClient.createAppointmentCalls.firstWhere((p) => p['p_type'] == 'planned');
      final start = DateTime.parse(firstPlanned['p_start_time'] as String).toLocal();
      expect(start.weekday, DateTime.monday);
    });

    test('fails when no patients exist', () async {
      final emptyPatients = FakePatientRepository(patients: []);
      final emptyService = AppointmentDevSeedService(
        appointments: AppointmentRepository(rpcClient),
        searchPatients: SearchPatients(emptyPatients),
        listStaff: ListStaff(staffAdmin),
        branches: branches,
      );

      final outcome = await emptyService.seed(branchId: branchId, organizationId: organizationId);

      expect(outcome.isSuccess, isFalse);
      expect(outcome.errorMessage, contains('No patients'));
      expect(rpcClient.createAppointmentCalls, isEmpty);
    });
  });
}

class FakeStaffAdminRepository implements StaffAdminRepository {
  FakeStaffAdminRepository({required this.staff});

  List<StaffListItem> staff;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async => staff;

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) => throw UnimplementedError();

  @override
  Future<bool> organizationHasOwner() => throw UnimplementedError();

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) =>
      throw UnimplementedError();
}

class _FakeBranchRepository implements BranchRepository {
  _FakeBranchRepository({required this.branchId, required this.workingSchedule});

  final String branchId;
  BranchWorkingSchedule workingSchedule;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    return [BranchListItem(id: branchId, name: 'Main', isActive: true, workingSchedule: workingSchedule)];
  }

  @override
  Future<String> createBranch(CreateBranchInput input) => throw UnimplementedError();

  @override
  Future<String> updateBranch(UpdateBranchInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) => throw UnimplementedError();
}
