import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_postgrest_rpc.dart';
import 'settings_table_test_client.dart';

/// [SupabaseClient] fake for V1-7 shift repository and create-page tests.
class ShiftRpcTestClient extends Fake implements SupabaseClient {
  ShiftRpcTestClient({
    Map<String, dynamic>? rpcResults,
    PostgrestException? rpcException,
    String? branchId,
    String? staffId,
  }) : rpcResults = rpcResults ?? {},
       rpcException = rpcException,
       branchId = branchId ?? '44444444-4444-4444-8444-444444444444',
       staffId = staffId ?? '22222222-2222-4222-8222-222222222222' {
    _tableClient = SettingsTableTestClient({
      'staff_branch_assignments': [
        {
          'staff_member_id': this.staffId,
          'branch_id': this.branchId,
          'is_deleted': false,
          'staff_members': {'id': this.staffId, 'full_name': 'Dr Shift', 'role': 'doctor', 'is_active': true},
        },
        {
          'staff_member_id': secondStaffId,
          'branch_id': this.branchId,
          'is_deleted': false,
          'staff_members': {'id': secondStaffId, 'full_name': 'Nurse Shift', 'role': 'receptionist', 'is_active': true},
        },
      ],
    });
    detailAssignments = [
      {'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'staff_member_id': this.staffId, 'display_name': 'Dr Shift'},
    ];
  }

  static const defaultShiftId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  static const secondStaffId = '33333333-3333-4333-8333-333333333333';

  Map<String, dynamic> rpcResults;
  PostgrestException? rpcException;
  final String branchId;
  final String staffId;

  final List<String> rpcLog = [];
  String? lastFunction;
  Map<String, dynamic>? lastParams;
  final Map<String, Map<String, dynamic>> paramsByFunction = {};

  /// Optional override payload for [get_shift_detail].
  Map<String, dynamic>? getShiftDetailOverride;

  /// Default calendar rows returned by [list_shifts] when no override is set.
  List<Map<String, dynamic>> listShiftsPayload = const [];

  /// When true, [list_shifts] throws [PostgrestException] with [listShiftsErrorMessage].
  bool listShiftsDenied = false;
  String listShiftsErrorMessage = 'permission_denied';

  /// Mutable assignment rows for [get_shift_detail] / [modify_shift_assignments] simulations.
  late List<Map<String, dynamic>> detailAssignments;

  DateTime detailUpdatedAt = DateTime.utc(2026, 6, 1, 10);

  String detailShiftDate = '2026-06-10';
  String detailStartTime = '09:00';
  String detailEndTime = '17:00';
  String? detailNotes;

  /// When set, [modify_shift_assignments] throws this exception.
  PostgrestException? modifyAssignmentsException;

  /// When set, [update_shift] throws this exception.
  PostgrestException? updateShiftException;

  /// When set, [cancel_shift] throws this exception.
  PostgrestException? cancelShiftException;

  bool shiftCancelled = false;

  late final SettingsTableTestClient _tableClient;

  @override
  SupabaseQueryBuilder from(String table) => _tableClient.from(table);

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    rpcLog.add(fn);
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    if (params != null) {
      paramsByFunction[fn] = Map<String, dynamic>.from(params);
    }

    if (rpcException != null && fn != 'modify_shift_assignments' && fn != 'update_shift' && fn != 'cancel_shift') {
      return _ThrowingPostgrestRpc(rpcException!) as PostgrestFilterBuilder<T>;
    }

    if (fn == 'modify_shift_assignments' && modifyAssignmentsException != null) {
      return _ThrowingPostgrestRpc(modifyAssignmentsException!) as PostgrestFilterBuilder<T>;
    }

    if (fn == 'update_shift' && updateShiftException != null) {
      return _ThrowingPostgrestRpc(updateShiftException!) as PostgrestFilterBuilder<T>;
    }

    if (fn == 'cancel_shift' && cancelShiftException != null) {
      return _ThrowingPostgrestRpc(cancelShiftException!) as PostgrestFilterBuilder<T>;
    }

    final override = rpcResults[fn];
    if (override is PostgrestException) {
      return _ThrowingPostgrestRpc(override) as PostgrestFilterBuilder<T>;
    }

    if (fn == 'list_shifts' && listShiftsDenied) {
      return _ThrowingPostgrestRpc(PostgrestException(message: listShiftsErrorMessage, code: 'P0001'))
          as PostgrestFilterBuilder<T>;
    }

    return FakePostgrestRpc(_defaultPayload(fn, override)) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic>? paramsFor(String functionName) => paramsByFunction[functionName];

  dynamic _defaultPayload(String fn, dynamic override) {
    if (override != null) {
      return override;
    }
    if (fn == 'get_shift_detail' && getShiftDetailOverride != null) {
      return getShiftDetailOverride;
    }
    return switch (fn) {
      'create_shift' => defaultShiftId,
      'modify_shift_assignments' => _applyModifyAssignments(lastParams),
      'update_shift' => _applyUpdateShift(lastParams),
      'cancel_shift' => _applyCancelShift(),
      'get_shift_detail' => _buildShiftDetail(),
      'list_shifts' =>
        listShiftsPayload.where((row) => row['status']?.toString() != 'cancelled').toList(growable: false),
      _ => {'success': false, 'error_code': 'UNKNOWN', 'error_message': 'Unhandled RPC $fn'},
    };
  }

  Map<String, dynamic> _buildShiftDetail() {
    if (getShiftDetailOverride != null) {
      return getShiftDetailOverride!;
    }

    final assigneeCount = detailAssignments.length;
    final status = assigneeCount == 0 ? 'incomplete' : 'active';

    return {
      'shift': {
        'id': defaultShiftId,
        'branch_id': branchId,
        'shift_date': detailShiftDate,
        'start_time': detailStartTime,
        'end_time': detailEndTime,
        'notes': detailNotes,
        'status': shiftCancelled ? 'cancelled' : status,
        'is_unassigned': assigneeCount == 0,
        'is_past': false,
        'is_read_only': shiftCancelled,
        'updated_at': detailUpdatedAt.toUtc().toIso8601String(),
      },
      'assignments': List<Map<String, dynamic>>.from(detailAssignments),
      'branch': {'id': branchId, 'name': 'Main Branch', 'code': 'MAIN'},
    };
  }

  Map<String, dynamic> _applyModifyAssignments(Map<String, dynamic>? params) {
    final removeIds = (params?['p_remove_staff_ids'] as List?)?.map((id) => id.toString()).toSet() ?? <String>{};
    final addIds = (params?['p_add_staff_ids'] as List?)?.map((id) => id.toString()).toList() ?? <String>[];

    detailAssignments = detailAssignments
        .where((row) => !removeIds.contains(row['staff_member_id']?.toString()))
        .toList();

    for (final staffIdToAdd in addIds) {
      if (detailAssignments.any((row) => row['staff_member_id']?.toString() == staffIdToAdd)) {
        continue;
      }
      final displayName = staffIdToAdd == secondStaffId ? 'Nurse Shift' : 'Dr Shift';
      detailAssignments = [
        ...detailAssignments,
        {
          'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccc${detailAssignments.length}',
          'staff_member_id': staffIdToAdd,
          'display_name': displayName,
        },
      ];
    }

    detailUpdatedAt = detailUpdatedAt.add(const Duration(minutes: 1));
    final assigneeCount = detailAssignments.length;

    return {
      'shift_id': defaultShiftId,
      'status': assigneeCount == 0 ? 'incomplete' : 'active',
      'assignee_count': assigneeCount,
      'updated_at': detailUpdatedAt.toUtc().toIso8601String(),
    };
  }

  dynamic _applyUpdateShift(Map<String, dynamic>? params) {
    if (params != null) {
      final date = params['p_shift_date']?.toString();
      final start = params['p_start_time']?.toString();
      final end = params['p_end_time']?.toString();
      if (date != null && date.isNotEmpty) {
        detailShiftDate = date;
      }
      if (start != null && start.isNotEmpty) {
        detailStartTime = start;
      }
      if (end != null && end.isNotEmpty) {
        detailEndTime = end;
      }
      if (params.containsKey('p_notes')) {
        final notes = params['p_notes']?.toString().trim();
        detailNotes = notes == null || notes.isEmpty ? null : notes;
      }
    }
    detailUpdatedAt = detailUpdatedAt.add(const Duration(minutes: 1));
    return null;
  }

  dynamic _applyCancelShift() {
    shiftCancelled = true;
    detailUpdatedAt = detailUpdatedAt.add(const Duration(minutes: 1));
    return null;
  }
}

class _ThrowingPostgrestRpc extends Fake implements PostgrestFilterBuilder<dynamic> {
  _ThrowingPostgrestRpc(this.exception);

  final PostgrestException exception;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<dynamic>.error(exception).then(onValue, onError: onError);
  }
}
