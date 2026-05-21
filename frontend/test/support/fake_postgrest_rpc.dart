import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal [PostgrestFilterBuilder] fake for `await client.rpc(...)` in repository tests.
class FakePostgrestRpc extends Fake implements PostgrestFilterBuilder<dynamic> {
  FakePostgrestRpc(this.result);

  final dynamic result;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<dynamic>.value(result).then(onValue, onError: onError);
  }
}

/// [SupabaseClient] that records RPC calls and returns [FakePostgrestRpc].
class RpcCaptureSupabaseClient extends Fake implements SupabaseClient {
  String? lastFunction;
  Map<String, dynamic>? lastParams;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    return FakePostgrestRpc(_payloadFor(fn, params)) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _payloadFor(String fn, Map<String, dynamic>? params) {
    if (fn == 'bootstrap_create_organization') {
      return {
        'success': true,
        'data': {'organization_id': '11111111-1111-4111-8111-111111111111'},
      };
    }
    if (fn == 'bootstrap_create_branch') {
      return {
        'success': true,
        'data': {'branch_id': '22222222-2222-4222-8222-222222222222'},
      };
    }
    return {
      'success': true,
      'data': {
        'staff_member_id': '33333333-3333-4333-8333-333333333333',
        'assigned_password': params?['p_password'] ?? params?['p_new_password'] ?? 'secret',
      },
    };
  }
}
