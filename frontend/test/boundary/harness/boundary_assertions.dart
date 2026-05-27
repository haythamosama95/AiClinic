import 'package:flutter_test/flutter_test.dart';
import 'package:postgrest/postgrest.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';

bool _isUnauthenticatedPostgrest(String expectedCode, String? actualCode) =>
    expectedCode == 'FORBIDDEN' && actualCode == 'PGRST301';

Future<void> expectRpcCode(Future<void> Function() run, String code) async {
  try {
    await run();
    fail('Expected RpcFailure($code)');
  } on RpcFailure catch (failure) {
    // Signed-out / invalid JWT hits PostgREST before RPC body is evaluated.
    if (_isUnauthenticatedPostgrest(code, failure.code)) {
      return;
    }
    expect(failure.code, code);
  } on PostgrestException catch (error) {
    if (_isUnauthenticatedPostgrest(code, error.code)) {
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
    if (!_isUnauthenticatedPostgrest(code, failure.code)) {
      expect(failure.code, code);
    }
  }
  throw StateError('unreachable');
}

RpcFailure? rpcFailureOrNull(Object? error) => error is RpcFailure ? error : null;
