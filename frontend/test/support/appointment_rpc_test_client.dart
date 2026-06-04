import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_postgrest_rpc.dart';

/// [SupabaseClient] fake for V1-4 appointment repository RPC unit tests.
class AppointmentRpcTestClient extends RpcCaptureSupabaseClient {
  AppointmentRpcTestClient({Map<String, Map<String, dynamic>>? rpcResults}) : rpcResults = rpcResults ?? {};

  final Map<String, Map<String, dynamic>> rpcResults;
  final List<Map<String, dynamic>> createAppointmentCalls = [];
  final Map<String, int> rpcCallCounts = {};

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    rpcCallCounts[fn] = (rpcCallCounts[fn] ?? 0) + 1;
    if (fn == 'create_appointment' && lastParams != null) {
      createAppointmentCalls.add(Map<String, dynamic>.from(lastParams!));
    }
    final override = rpcResults[fn];
    final payload = override ?? _defaultPayload(fn);
    return FakePostgrestRpc(payload) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _defaultPayload(String fn) {
    return switch (fn) {
      'get_appointment_settings' => {
        'success': true,
        'data': {
          'default_duration_minutes': 20,
          'min_duration_minutes': 5,
          'max_duration_minutes': 240,
          'working_schedule': {
            'days': [
              for (final day in ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'])
                {'day': day, 'is_working_day': true, 'open_time': '06:00', 'close_time': '23:59'},
            ],
          },
        },
      },
      'set_appointment_default_duration' => {
        'success': true,
        'data': {'default_duration_minutes': lastParams?['p_duration_minutes'] ?? 20},
      },
      'create_appointment' => {
        'success': true,
        'data': {
          'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'start_time': '2026-06-01T10:00:00.000Z',
          'end_time': '2026-06-01T10:30:00.000Z',
          'status': 'scheduled',
          'type': lastParams?['p_type'] ?? 'planned',
        },
      },
      'list_appointments' => {
        'success': true,
        'data': {
          'items': [
            {
              'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
              'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'patient_name': 'Test Patient',
              'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              'doctor_name': 'Dr Test',
              'start_time': '2026-06-01T09:00:00.000Z',
              'end_time': '2026-06-01T09:30:00.000Z',
              'type': 'planned',
              'status': 'scheduled',
            },
          ],
        },
      },
      'update_appointment_status' => {
        'success': true,
        'data': {'appointment_id': lastParams?['p_appointment_id'], 'status': lastParams?['p_new_status']},
      },
      'reschedule_appointment' => {
        'success': true,
        'data': {
          'appointment_id': lastParams?['p_appointment_id'],
          'start_time': lastParams?['p_start_time'],
          'end_time': '2026-06-01T11:00:00.000Z',
        },
      },
      'cancel_appointment' => {
        'success': true,
        'data': {'appointment_id': lastParams?['p_appointment_id'], 'status': 'cancelled'},
      },
      _ => {'success': false, 'error_code': 'UNKNOWN', 'error_message': 'Unhandled RPC $fn'},
    };
  }
}
