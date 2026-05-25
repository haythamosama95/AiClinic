import 'dart:async';

import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ThrowingPostgrestRpc extends Fake implements PostgrestFilterBuilder<dynamic> {
  _ThrowingPostgrestRpc(this.exception);

  final PostgrestException exception;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<dynamic>.error(exception).then(onValue, onError: onError);
  }
}

class _PostgrestErrorClient extends Fake implements SupabaseClient {
  _PostgrestErrorClient({required this.exception});

  final PostgrestException exception;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    return _ThrowingPostgrestRpc(exception) as PostgrestFilterBuilder<T>;
  }
}

class _TestSettingsInvoker with AppRpcInvoker {
  _TestSettingsInvoker(this.client);

  final SupabaseClient client;

  @override
  SupabaseClient get rpcClient => client;

  @override
  String get migrationHint => '20260522100000_org_branch_management.sql';

  @override
  String get rpcLogDomain => 'settings';
}

void main() {
  group('AppRpcInvoker (settings migration hint)', () {
    test('maps missing RPC to RPC_NOT_APPLIED with migration hint', () async {
      final invoker = _TestSettingsInvoker(
        _PostgrestErrorClient(
          exception: const PostgrestException(
            message: 'Could not find the function public.update_organization',
            code: 'PGRST202',
          ),
        ),
      );

      expect(
        () => invoker.invokeRpc('update_organization', null),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.code, 'code', 'RPC_NOT_APPLIED')
              .having((e) => e.message, 'message', contains('20260522100000')),
        ),
      );
    });

    test('rethrows unrelated PostgREST errors', () async {
      final invoker = _TestSettingsInvoker(
        _PostgrestErrorClient(
          exception: const PostgrestException(message: 'permission denied', code: '42501'),
        ),
      );

      expect(
        () => invoker.invokeRpc('update_organization', null),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
      );
    });
  });
}
