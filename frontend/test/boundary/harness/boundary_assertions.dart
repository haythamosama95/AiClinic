import 'package:flutter_test/flutter_test.dart';
import 'package:postgrest/postgrest.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';

Future<void> expectRpcCode(Future<void> Function() run, String code) async {
  try {
    await run();
    fail('Expected RpcFailure($code)');
  } on RpcFailure catch (failure) {
    expect(failure.code, code);
  } on PostgrestException catch (error) {
    // Signed-out / invalid JWT hits PostgREST before RPC body is evaluated.
    if (code == 'FORBIDDEN' && error.code == 'PGRST301') {
      return;
    }
    rethrow;
  }
}

Future<T> expectRpcCodeReturns<T>(Future<T> Function() run, String code) async {
  try {
    await run();
    fail('Expected RpcFailure($code)');
  } on RpcFailure catch (failure) {
    expect(failure.code, code);
  }
  throw StateError('unreachable');
}

RpcFailure? rpcFailureOrNull(Object? error) => error is RpcFailure ? error : null;
