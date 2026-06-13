import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_postgrest_rpc.dart';

/// [SupabaseClient] fake for V1-2 settings repository RPC unit tests.
class SettingsRpcTestClient extends RpcCaptureSupabaseClient {
  SettingsRpcTestClient({Map<String, Map<String, dynamic>>? rpcResults, this.rpcException})
    : rpcResults = rpcResults ?? {};

  final Map<String, Map<String, dynamic>> rpcResults;
  final PostgrestException? rpcException;

  /// Every RPC invocation in call order (for batch-save tests).
  final List<({String function, Map<String, dynamic>? params})> rpcCalls = [];

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    rpcCalls.add((function: fn, params: params == null ? null : Map<String, dynamic>.from(params)));
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    if (rpcException != null) {
      return _ThrowingPostgrestRpc(rpcException!) as PostgrestFilterBuilder<T>;
    }
    final override = rpcResults[fn];
    final payload = override ?? _defaultRpcPayload(fn);
    return FakePostgrestRpc(payload) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _defaultRpcPayload(String fn) {
    return switch (fn) {
      'update_organization' => {
        'success': true,
        'data': {'organization_id': '11111111-1111-4111-8111-111111111111'},
      },
      'manage_create_branch' => {
        'success': true,
        'data': {'branch_id': '44444444-4444-4444-8444-444444444444'},
      },
      'update_branch' => {
        'success': true,
        'data': {'branch_id': paramsId('p_branch_id')},
      },
      'set_branch_active' => {
        'success': true,
        'data': {'branch_id': paramsId('p_branch_id'), 'is_active': lastParams?['p_is_active']},
      },
      'update_staff_member' => {
        'success': true,
        'data': {'staff_member_id': paramsId('p_staff_member_id')},
      },
      'set_staff_active' => {
        'success': true,
        'data': {'staff_member_id': paramsId('p_staff_member_id'), 'is_active': lastParams?['p_is_active']},
      },
      'delete_staff_member' => {
        'success': true,
        'data': {'staff_member_id': paramsId('p_staff_member_id')},
      },
      'update_role_permission' => {
        'success': true,
        'data': {
          'role': lastParams?['p_role'],
          'permission_key': lastParams?['p_permission_key'],
          'is_granted': lastParams?['p_is_granted'],
        },
      },
      'get_appointment_settings' => {
        'success': true,
        'data': {'default_duration_minutes': 20, 'min_duration_minutes': 5, 'max_duration_minutes': 240},
      },
      'set_appointment_default_duration' => {
        'success': true,
        'data': {'default_duration_minutes': lastParams?['p_duration_minutes'] ?? 20},
      },
      _ => {'success': true, 'data': {}},
    };
  }

  String paramsId(String key) => lastParams?[key]?.toString() ?? '00000000-0000-4000-8000-000000000099';
}

class _ThrowingPostgrestRpc extends Fake implements PostgrestFilterBuilder<dynamic> {
  _ThrowingPostgrestRpc(this.exception);

  final PostgrestException exception;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<dynamic>.error(exception).then(onValue, onError: onError);
  }
}

/// Client that returns a fixed row from [maybeSingle] for organization fetch tests.
class OrganizationFetchTestClient extends Fake implements SupabaseClient {
  OrganizationFetchTestClient(this.row);

  final Map<String, dynamic>? row;

  @override
  SupabaseQueryBuilder from(String table) {
    assert(table == 'organizations');
    return _OrganizationQueryBuilder(row);
  }
}

class _OrganizationQueryBuilder extends Fake implements SupabaseQueryBuilder {
  _OrganizationQueryBuilder(this.row);

  final Map<String, dynamic>? row;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    return _OrganizationFilterBuilder(row);
  }
}

class _OrganizationFilterBuilder extends Fake implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _OrganizationFilterBuilder(this.row);

  final Map<String, dynamic>? row;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object value) => this;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return _MaybeSingleBuilder(row);
  }
}

class _MaybeSingleBuilder extends Fake implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  _MaybeSingleBuilder(this.row);

  final Map<String, dynamic>? row;

  @override
  Future<R> then<R>(FutureOr<R> Function(Map<String, dynamic>? value) onValue, {Function? onError}) {
    return Future<Map<String, dynamic>?>.value(row).then(onValue, onError: onError);
  }
}
