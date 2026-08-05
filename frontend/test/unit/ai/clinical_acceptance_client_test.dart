import 'dart:async';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/ai/acceptance/clinical_accept_controller.dart';
import 'package:ai_clinic/features/ai/acceptance/clinical_acceptance_client.dart';
import 'package:ai_clinic/features/ai/acceptance/clinical_acceptance_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest_rpc.dart';

class _ThrowingPostgrestRpc extends Fake implements PostgrestFilterBuilder<dynamic> {
  _ThrowingPostgrestRpc(this.exception);

  final PostgrestException exception;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<dynamic>.error(exception).then(onValue, onError: onError);
  }
}

/// [RpcCaptureSupabaseClient] that throws [rpcException] when set.
class _ThrowingRpcCaptureClient extends RpcCaptureSupabaseClient {
  PostgrestException? rpcException;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    if (rpcException != null) {
      return _ThrowingPostgrestRpc(rpcException!) as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _SpyClinicalAcceptancePort implements ClinicalAcceptancePort {
  final List<String> calls = [];

  @override
  Future<RpcResult> recordAcceptance({
    required String requestReference,
    required String targetKey,
    required Map<String, dynamic> targetArgs,
  }) async {
    calls.add(requestReference);
    return const RpcResult(success: true, data: {});
  }
}

void main() {
  group('clinical acceptance client', () {
    test('maps record_ai_acceptance RPC parameters', () async {
      final client = RpcCaptureSupabaseClient();
      final acceptanceClient = ClinicalAcceptanceClient(client: client);

      await acceptanceClient.recordAcceptance(
        requestReference: 'A1B2-C3D4',
        targetKey: 'visit_clinical_notes',
        targetArgs: {
          'p_visit_id': '550e8400-e29b-41d4-a716-446655440000',
          'p_complaint': 'Accepted note',
          'p_expected_updated_at': '2026-08-01T10:00:00.000Z',
        },
      );

      expect(client.lastFunction, 'record_ai_acceptance');
      expect(client.lastParams?['p_request_reference'], 'A1B2-C3D4');
      expect(client.lastParams?['p_target_key'], 'visit_clinical_notes');
      expect(
        client.lastParams?['p_target_args'],
        isA<Map<String, dynamic>>()
            .having((m) => m['p_visit_id'], 'visit id', '550e8400-e29b-41d4-a716-446655440000')
            .having((m) => m['p_complaint'], 'complaint', 'Accepted note'),
      );
    });

    test('discard and idle paths never invoke the acceptance port', () {
      final spy = _SpyClinicalAcceptancePort();
      final controller = ClinicalAcceptController(port: spy);

      expect(spy.calls, isEmpty);

      controller.stageDraft(requestReference: 'A1B2-C3D4', complaint: 'Staged draft');
      expect(controller.hasStagedDraft, isTrue);

      controller.discard();
      expect(controller.hasStagedDraft, isFalse);
      expect(spy.calls, isEmpty);
    });

    test('returns RpcResult failure when Supabase throws PostgrestException', () async {
      final client = _ThrowingRpcCaptureClient()
        ..rpcException = const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        );
      final acceptanceClient = ClinicalAcceptanceClient(client: client);

      final result = await acceptanceClient.recordAcceptance(
        requestReference: 'A1B2-C3D4',
        targetKey: 'visit_clinical_notes',
        targetArgs: {
          'p_visit_id': '550e8400-e29b-41d4-a716-446655440000',
          'p_complaint': 'Accepted note',
          'p_expected_updated_at': '2026-08-01T10:00:00.000Z',
        },
      );

      expect(result.success, isFalse);
      expect(result.errorCode, '23505');
      expect(result.errorMessage, contains('duplicate key'));
      expect(client.lastFunction, 'record_ai_acceptance');
    });
  });
}
