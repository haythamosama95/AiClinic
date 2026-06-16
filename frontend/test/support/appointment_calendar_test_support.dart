import 'dart:async';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'appointment_rpc_test_client.dart';
import 'fake_postgrest_rpc.dart';

const calendarTestBranchAId = '00000000-0000-4000-8000-000000000001';
const calendarTestBranchBId = '00000000-0000-4000-8000-000000000002';
const calendarTestBranchCId = '00000000-0000-4000-8000-000000000003';
const calendarTestDoctorAId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const calendarTestDoctorBId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';

const calendarTestDoctors = [
  StaffListItem(id: calendarTestDoctorAId, fullName: 'Dr. Ada', role: StaffRole.doctor, isActive: true),
  StaffListItem(id: calendarTestDoctorBId, fullName: 'Dr. Ben', role: StaffRole.doctor, isActive: true),
];

/// Delays [list_appointments] responses for loading-state widget tests.
class SlowAppointmentRpcTestClient extends AppointmentRpcTestClient {
  SlowAppointmentRpcTestClient({this.listDelay = const Duration(milliseconds: 400)});

  final Duration listDelay;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments') {
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      final payload = rpcResults[fn] ?? calendarListAppointmentsDefaultPayload();
      return _DelayedFakePostgrestRpc(payload, listDelay) as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

/// Fails the first [list_appointments] call, then succeeds.
class FlakyListAppointmentRpcClient extends AppointmentRpcTestClient {
  FlakyListAppointmentRpcClient({this.failuresBeforeSuccess = 1});

  int failuresBeforeSuccess;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments' && failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      rpcLog.add(fn);
      lastFunction = fn;
      lastParams = params == null ? null : Map<String, dynamic>.from(params);
      rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
      return FakePostgrestRpc({'success': false, 'error_code': 'INTERNAL', 'error_message': 'Temporary list failure'})
          as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

/// Returns different appointment rows per doctor filter.
class DoctorAwareAppointmentRpcClient extends AppointmentRpcTestClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments') {
      final doctorId = params?['p_doctor_id']?.toString();
      final items = switch (doctorId) {
        calendarTestDoctorAId => [
          appointmentRpcDefaultListItem(
            patientName: 'Ada Patient',
            doctorId: calendarTestDoctorAId,
            doctorName: 'Dr. Ada',
          ),
        ],
        calendarTestDoctorBId => [
          appointmentRpcDefaultListItem(
            patientName: 'Ben Patient',
            doctorId: calendarTestDoctorBId,
            doctorName: 'Dr. Ben',
            id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccd',
          ),
        ],
        _ => [
          appointmentRpcDefaultListItem(
            patientName: 'Ada Patient',
            doctorId: calendarTestDoctorAId,
            doctorName: 'Dr. Ada',
          ),
          appointmentRpcDefaultListItem(
            patientName: 'Ben Patient',
            doctorId: calendarTestDoctorBId,
            doctorName: 'Dr. Ben',
            id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccd',
          ),
        ],
      };
      rpcResults[fn] = {
        'success': true,
        'data': {'items': items},
      };
    }
    return super.rpc(fn, params: params, get: get);
  }
}

/// Returns different appointment rows per branch id.
class BranchAwareAppointmentRpcClient extends AppointmentRpcTestClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'list_appointments') {
      final branchId = params?['p_branch_id']?.toString();
      final patientName = switch (branchId) {
        calendarTestBranchBId => 'Branch B Patient',
        calendarTestBranchCId => 'Branch C Patient',
        _ => 'Branch A Patient',
      };
      rpcResults[fn] = {
        'success': true,
        'data': {
          'items': [appointmentRpcDefaultListItem(patientName: patientName)],
        },
      };
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _DelayedFakePostgrestRpc extends FakePostgrestRpc {
  _DelayedFakePostgrestRpc(super.result, this.delay);

  final Duration delay;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<void>.delayed(delay).then((_) => super.then(onValue, onError: onError));
  }
}

class CalendarStubBranchRepository implements BranchRepository {
  CalendarStubBranchRepository({this.branches});

  final List<BranchListItem>? branches;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    return branches ??
        [
          BranchListItem(
            id: calendarTestBranchAId,
            name: 'Main',
            code: 'M1',
            isActive: true,
            workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          ),
          BranchListItem(
            id: calendarTestBranchBId,
            name: 'North',
            code: 'N1',
            isActive: true,
            workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          ),
        ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CalendarStubStaffRepository implements StaffAdminRepository {
  CalendarStubStaffRepository({this.doctors});

  final List<StaffListItem>? doctors;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async => doctors ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CalendarDoctorsStubStaffRepository extends CalendarStubStaffRepository {
  CalendarDoctorsStubStaffRepository({List<StaffListItem>? doctors}) : super(doctors: doctors ?? calendarTestDoctors);
}

class SlowCalendarStubBranchRepository extends CalendarStubBranchRepository {
  SlowCalendarStubBranchRepository({this.listDelay = const Duration(milliseconds: 400), super.branches});

  final Duration listDelay;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    await Future<void>.delayed(listDelay);
    return super.listBranches(organizationId: organizationId, filter: filter);
  }
}

class EmptyCalendarStubBranchRepository implements BranchRepository {
  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> calendarListAppointmentsDefaultPayload({String patientName = 'Test Patient'}) {
  return {
    'success': true,
    'data': {
      'items': [appointmentRpcDefaultListItem(patientName: patientName)],
    },
  };
}
