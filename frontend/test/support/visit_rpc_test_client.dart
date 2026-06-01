import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_postgrest_rpc.dart';

/// [SupabaseClient] fake for V1-5 visit repository unit tests.
class VisitRpcTestClient extends RpcCaptureSupabaseClient {
  VisitRpcTestClient({Map<String, Map<String, dynamic>>? rpcResults}) : rpcResults = rpcResults ?? {};

  final Map<String, Map<String, dynamic>> rpcResults;
  final List<String> rpcLog = [];
  final List<({String fn, Map<String, dynamic>? params})> rpcCalls = [];

  /// Params from the most recent call to [fn], if any.
  Map<String, dynamic>? paramsForFunction(String fn) {
    for (var i = rpcCalls.length - 1; i >= 0; i--) {
      if (rpcCalls[i].fn == fn) {
        return rpcCalls[i].params;
      }
    }
    return null;
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    rpcLog.add(fn);
    final copied = params == null ? null : Map<String, dynamic>.from(params);
    rpcCalls.add((fn: fn, params: copied));
    lastFunction = fn;
    lastParams = copied;
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
      'complete_visit' => {
        'success': true,
        'data': {
          'visit_id': lastParams?['p_visit_id'] ?? 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'visit_status': 'completed',
          'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'appointment_status': 'completed',
        },
      },
      'get_specialty_form_schema' => {
        'success': true,
        'data': {
          'schema_json': {
            'type': 'object',
            'properties': {
              'pain_score': {'type': 'number', 'title': 'Pain score'},
              'follow_up': {'type': 'boolean', 'title': 'Follow up'},
              'site': {
                'type': 'string',
                'title': 'Site',
                'enum': ['arm', 'leg'],
              },
            },
            'required': ['pain_score'],
          },
        },
      },
      'set_specialty_form_schema' => {
        'success': true,
        'data': {
          'schema_json': {
            'type': 'object',
            'properties': {
              'pain_score': {'type': 'number', 'title': 'Pain score'},
            },
          },
        },
      },
      'list_patient_visits' => {
        'success': true,
        'data': {
          'items': [
            {
              'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
              'visit_date': '2026-05-31',
              'doctor_name': 'Dr Test',
              'status': 'completed',
              'branch_name': 'Main',
            },
          ],
          'total_count': 1,
          'limit': lastParams?['p_limit'] ?? 50,
          'offset': lastParams?['p_offset'] ?? 0,
        },
      },
      'create_treatment_plan' => {
        'success': true,
        'data': {'treatment_plan_id': 'tttttttt-tttt-4ttt-8ttt-tttttttttttt'},
      },
      'update_treatment_plan' => {'success': true, 'data': {}},
      'archive_treatment_plan' => {'success': true, 'data': {}},
      'register_visit_attachment' => {
        'success': true,
        'data': {'attachment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'},
      },
      'get_visit_attachment_download' => {
        'success': true,
        'data': {
          'signed_url': 'https://example.test/download',
          'file_path': 'org-1/branch-1/visit-1/lab-result.pdf',
          'file_type': 'pdf',
          'filename': 'lab-result.pdf',
          'expires_at': '2026-05-31T12:00:00.000Z',
        },
      },
      _ => {'success': false, 'error_code': 'UNKNOWN', 'error_message': 'Unhandled RPC $fn'},
    };
  }
}
