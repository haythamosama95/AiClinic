import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_postgrest_rpc.dart';

/// [SupabaseClient] fake for V1-3 patient repository RPC unit tests.
class PatientRpcTestClient extends RpcCaptureSupabaseClient {
  PatientRpcTestClient({Map<String, Map<String, dynamic>>? rpcResults}) : rpcResults = rpcResults ?? {};

  final Map<String, Map<String, dynamic>> rpcResults;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    final override = rpcResults[fn];
    final payload = override ?? _defaultPayload(fn);
    return FakePostgrestRpc(payload) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _defaultPayload(String fn) {
    return switch (fn) {
      'search_patients' => {
        'success': true,
        'data': {
          'items': [
            {
              'id': '11111111-1111-4111-8111-111111111111',
              'full_name': 'Test Patient',
              'phone': '201234567890',
              'date_of_birth': '1990-01-01',
              'branch_id': '44444444-4444-4444-8444-444444444444',
              'branch_name': 'Main',
            },
          ],
          'total_count': 1,
          'limit': lastParams?['p_limit'] ?? 25,
          'offset': lastParams?['p_offset'] ?? 0,
        },
      },
      'get_patient' => {
        'success': true,
        'data': {
          'id': _param('p_patient_id'),
          'full_name': 'Test Patient',
          'branch_id': '44444444-4444-4444-8444-444444444444',
          'branch_name': 'Main',
          'created_at': '2026-01-01T00:00:00.000Z',
          'updated_at': '2026-01-02T00:00:00.000Z',
        },
      },
      'check_patient_duplicates' => {
        'success': true,
        'data': {
          'candidates': [
            {'id': '22222222-2222-4222-8222-222222222222', 'full_name': 'Duplicate', 'branch_name': 'Main'},
          ],
        },
      },
      'create_patient' => {
        'success': true,
        'data': {'patient_id': '33333333-3333-4333-8333-333333333333'},
      },
      'update_patient' => {
        'success': true,
        'data': {'patient_id': _param('p_patient_id'), 'updated_at': '2026-01-03T00:00:00.000Z'},
      },
      'archive_patient' => {
        'success': true,
        'data': {'patient_id': _param('p_patient_id')},
      },
      _ => {'success': true, 'data': {}},
    };
  }

  String _param(String key) => lastParams?[key]?.toString() ?? '00000000-0000-4000-8000-000000000099';
}
