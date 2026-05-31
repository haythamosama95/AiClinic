import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_postgrest_rpc.dart';

/// [SupabaseClient] fake for V1-5 visit repository unit tests.
class VisitRpcTestClient extends RpcCaptureSupabaseClient {
  VisitRpcTestClient({Map<String, Map<String, dynamic>>? rpcResults}) : rpcResults = rpcResults ?? {};

  final Map<String, Map<String, dynamic>> rpcResults;
  final List<String> rpcLog = [];

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    rpcLog.add(fn);
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    final override = rpcResults[fn];
    final payload = override ?? _defaultPayload(fn);
    return FakePostgrestRpc(payload) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _defaultPayload(String fn) {
    return switch (fn) {
      'create_visit' => {
        'success': true,
        'data': {
          'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'appointment_id': lastParams?['p_appointment_id'],
          'status': 'in_progress',
          'visit_date': '2026-05-31',
        },
      },
      'get_visit_by_appointment' => {
        'success': true,
        'data': {'visit_id': null, 'status': null},
      },
      'get_visit' => {
        'success': true,
        'data': {
          'id': lastParams?['p_visit_id'] ?? 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'branch_id': '44444444-4444-4444-8444-444444444444',
          'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'doctor_name': 'Dr Test',
          'visit_date': '2026-05-31',
          'status': 'in_progress',
          'soap': {
            'subjective': null,
            'objective': null,
            'assessment': null,
            'plan': null,
            'specialty_form_json': {},
            'updated_at': '2026-05-31T10:00:00.000Z',
          },
        },
      },
      'save_soap_note' => {
        'success': true,
        'data': {
          'visit_id': lastParams?['p_visit_id'] ?? 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'updated_at': '2026-05-31T10:05:00.000Z',
        },
      },
      _ => {'success': false, 'error_code': 'UNKNOWN', 'error_message': 'Unhandled RPC $fn'},
    };
  }
}
