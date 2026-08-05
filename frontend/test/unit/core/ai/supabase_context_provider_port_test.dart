import 'package:ai_clinic/core/ai/supabase_context_provider_port.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupabaseContextProviderPort', () {
    const visitId = '550e8400-e29b-41d4-a716-446655440000';

    test('calls get_visit_chief_complaint with injected visit id', () async {
      String? calledFn;
      Map<String, dynamic>? calledParams;
      final port = SupabaseContextProviderPort.withRpc(
        visitId: visitId,
        rpc: (fn, params) async {
          calledFn = fn;
          calledParams = params;
          return {
            'success': true,
            'data': {
              'visit_id': visitId,
              'complaint': 'Headache',
              'recorded_at': '2026-07-31T12:00:00.000Z',
            },
          };
        },
      );

      final payload = await port.fetchVisitChiefComplaint();

      expect(calledFn, SupabaseContextProviderPort.rpcName);
      expect(calledParams, {'p_visit_id': visitId});
      expect(payload['visit_id'], visitId);
      expect(payload['complaint'], 'Headache');
      expect(payload['recorded_at'], '2026-07-31T12:00:00.000Z');
    });

    test('throws RpcFailure when RPC success is false', () async {
      final port = SupabaseContextProviderPort.withRpc(
        visitId: visitId,
        rpc: (fn, params) async => {
          'success': false,
          'error_code': 'FORBIDDEN',
          'error_message': 'out of scope',
        },
      );

      await expectLater(
        port.fetchVisitChiefComplaint(),
        throwsA(
          isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN'),
        ),
      );
    });
  });
}
