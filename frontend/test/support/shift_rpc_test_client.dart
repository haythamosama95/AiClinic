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
      ],
    });
  }

  static const defaultShiftId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

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

    if (rpcException != null) {
      return _ThrowingPostgrestRpc(rpcException!) as PostgrestFilterBuilder<T>;
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
      'get_shift_detail' => {
        'shift': {
          'id': defaultShiftId,
          'branch_id': branchId,
          'shift_date': lastParams?['p_shift_date'] ?? '2026-06-10',
          'start_time': lastParams?['p_start_time'] ?? '09:00',
          'end_time': lastParams?['p_end_time'] ?? '17:00',
          'notes': null,
          'status': 'active',
          'is_unassigned': false,
          'is_past': false,
          'is_read_only': false,
          'updated_at': '2026-06-01T10:00:00.000Z',
        },
        'assignments': [
          {'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'staff_member_id': staffId, 'display_name': 'Dr Shift'},
        ],
        'branch': {'id': branchId, 'name': 'Main Branch', 'code': 'MAIN'},
      },
      'list_shifts' =>
        listShiftsPayload.where((row) => row['status']?.toString() != 'cancelled').toList(growable: false),
      _ => {'success': false, 'error_code': 'UNKNOWN', 'error_message': 'Unhandled RPC $fn'},
    };
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
