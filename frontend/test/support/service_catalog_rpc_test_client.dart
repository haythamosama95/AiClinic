import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_postgrest_rpc.dart';

/// Configurable [SupabaseClient] fake for service-catalog repository tests.
class ServiceCatalogRpcTestClient extends RpcCaptureSupabaseClient {
  ServiceCatalogRpcTestClient({Map<String, Map<String, dynamic>>? rpcResults}) : rpcResults = rpcResults ?? {};

  final Map<String, Map<String, dynamic>> rpcResults;
  final List<String> rpcLog = [];

  Map<String, dynamic>? paramsForFunction(String fn) {
    for (var i = rpcLog.length - 1; i >= 0; i--) {
      if (rpcLog[i] == fn) {
        return lastParams;
      }
    }
    return null;
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    lastFunction = fn;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    rpcLog.add(fn);
    return FakePostgrestRpc(_payloadFor(fn)) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _payloadFor(String fn) {
    return rpcResults[fn] ?? _defaultPayloadFor(fn);
  }

  Map<String, dynamic> _defaultPayloadFor(String fn) {
    return switch (fn) {
      'create_service' => {
        'success': true,
        'data': {
          'service_id': 'service-1',
          'assigned_branch_ids': ['branch-1'],
        },
      },
      'get_service' => {
        'success': true,
        'data': {
          'service': {
            'id': 'service-1',
            'name': 'Consultation',
            'default_price': '200.00',
            'global_status': 'active',
            'created_at': '2026-01-01T10:00:00.000Z',
            'updated_at': '2026-01-02T10:00:00.000Z',
          },
          'branches': [
            {
              'service_branch_id': 'sb-1',
              'branch_id': 'branch-1',
              'status': 'active',
              'price_override': null,
              'promotion_price': null,
              'promotion_start_date': null,
              'promotion_end_date': null,
              'updated_at': '2026-01-01T10:00:00.000Z',
            },
          ],
        },
      },
      'set_service_branch_assignment' => {
        'success': true,
        'data': _branchAssignmentPayload(lastParams),
      },
      'configure_service_branch' => {
        'success': true,
        'data': {'service_branch_id': 'sb-1', 'updated_at': '2026-01-02T10:00:00.000Z'},
      },
      'set_service_promotion' => {
        'success': true,
        'data': {'service_branch_id': 'sb-1', 'has_promotion': true, 'updated_at': '2026-01-03T10:00:00.000Z'},
      },
      'resolve_effective_service_price' => {
        'success': true,
        'data': {'eligible': true, 'unit_price': '150.00', 'applied_rule': 'default', 'reason': null},
      },
      'search_eligible_services' => {
        'success': true,
        'data': {
          'items': [
            {
              'service_id': 'service-1',
              'name': 'Consultation',
              'unit_price': '200.00',
              'applied_rule': 'default',
              'on_promotion': false,
            },
            {'service_id': 'invalid-row'},
          ],
        },
      },
      'add_invoice_item_from_service' => {
        'success': true,
        'data': {
          'item_id': 'item-1',
          'quantity': '1',
          'unit_price': '200.00',
          'applied_rule': 'default',
        },
      },
      'update_service' => {
        'success': true,
        'data': {'service_id': 'service-1', 'updated_at': '2026-01-02T10:00:00.000Z'},
      },
      'set_service_global_status' => {
        'success': true,
        'data': {'service_id': 'service-1', 'global_status': 'inactive', 'updated_at': '2026-01-02T10:00:00.000Z'},
      },
      'soft_delete_service' => {
        'success': true,
        'data': {'service_id': 'service-1'},
      },
      'list_services' => {
        'success': true,
        'data': {
          'total': 2,
          'items': [
            {
              'service_id': 'service-1',
              'name': 'Consultation',
              'default_price': '200.00',
              'global_status': 'active',
              'assigned_branch_count': 1,
              'updated_at': '2026-01-01T10:00:00.000Z',
            },
            {'name': 'missing id'},
            {
              'service_id': 'service-2',
              'name': 'X-Ray',
              'default_price': '200.00',
              'global_status': 'active',
              'assigned_branch_count': 1,
              'updated_at': '2026-01-01T10:00:00.000Z',
            },
          ],
        },
      },
      'copy_service_branch_configuration' => {
        'success': true,
        'data': {
          'affected_service_ids': ['service-1'],
          'created_count': 1,
          'overwritten_count': 0,
        },
      },
      'setup_new_branch_services' => {
        'success': true,
        'data': {
          'target_branch_id': 'branch-2',
          'assigned_service_ids': ['service-1'],
        },
      },
      _ => {'success': true, 'data': <String, dynamic>{}},
    };
  }

  Map<String, dynamic> _branchAssignmentPayload(Map<String, dynamic>? params) {
    final key = params?['p_assign'] == true ? 'assigned_branch_ids' : 'unassigned_branch_ids';
    final branchIds = params?['p_branch_ids'];
    final ids = branchIds is List
        ? List<String>.from(branchIds.map((id) => id.toString()))
        : <String>['branch-1'];
    return {key: ids};
  }
}
