import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/shifts/domain/shift_detail.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_overlap_conflict.dart';

/// Shift scheduling read-path RPC wrappers (V1-7).
class ShiftRepository {
  ShiftRepository(this._client);

  final SupabaseClient _client;

  static const _migrationHint = '20260606180000_shift_management.sql';
  static const _logDomain = 'shifts';

  Future<List<ShiftListItem>> listShifts({
    required String branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final id = branchId.trim();
    if (id.isEmpty) {
      throw _clientInputFailure('Branch id is required.');
    }

    final from = DateTime(dateFrom.year, dateFrom.month, dateFrom.day);
    final to = DateTime(dateTo.year, dateTo.month, dateTo.day);
    if (to.isBefore(from)) {
      throw _clientInputFailure('End date must be on or after the start date.');
    }

    final raw = await _invokeJsonRpc('list_shifts', {
      'p_branch_id': id,
      'p_date_from': _formatDate(from),
      'p_date_to': _formatDate(to),
    });

    if (raw is! List) {
      return const [];
    }

    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          ShiftListItem.fromRow(item)
        else if (item is Map)
          ShiftListItem.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<ShiftListItem>().toList(growable: false);
  }

  Future<String> createShift({
    required String branchId,
    required DateTime shiftDate,
    required String startTime,
    required String endTime,
    String? notes,
    List<String> staffIds = const [],
  }) async {
    final id = branchId.trim();
    if (id.isEmpty) {
      throw _clientInputFailure('Branch id is required.');
    }

    final start = startTime.trim();
    final end = endTime.trim();
    if (start.isEmpty || end.isEmpty) {
      throw _clientInputFailure('Start and end times are required.');
    }

    final raw = await _invokeJsonRpc('create_shift', {
      'p_branch_id': id,
      'p_shift_date': _formatDate(shiftDate),
      'p_start_time': start,
      'p_end_time': end,
      if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
      'p_staff_ids': staffIds,
    });

    final shiftId = raw?.toString().trim();
    if (shiftId == null || shiftId.isEmpty) {
      throw StateError('Shift was created but no shift id was returned.');
    }
    return shiftId;
  }

  static List<ShiftOverlapConflict> parseOverlapConflicts(String message) {
    return ShiftOverlapConflict.parseFromRpcMessage(message);
  }

  Future<ShiftDetail> getShiftDetail({required String shiftId}) async {
    final id = shiftId.trim();
    if (id.isEmpty) {
      throw _clientInputFailure('Shift id is required.');
    }

    final raw = await _invokeJsonRpc('get_shift_detail', {'p_shift_id': id});
    if (raw is! Map) {
      throw StateError('Shift detail was returned in an unexpected shape.');
    }

    final detail = ShiftDetail.fromRpcData(Map<String, dynamic>.from(raw));
    if (detail == null) {
      throw StateError('Shift detail was returned in an unexpected shape.');
    }
    return detail;
  }

  Future<dynamic> _invokeJsonRpc(String functionName, Map<String, dynamic> params) async {
    AppLog.fine('$_logDomain.rpc.invoke fn=$functionName params=${params.keys.join(',')}');

    try {
      return await _client.rpc(functionName, params: params);
    } on AuthException catch (error) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'AUTH_ERROR', errorMessage: error.message));
    } on PostgrestException catch (error) {
      final message = error.message;
      if (error.code == 'PGRST202' || message.contains('Could not find the function')) {
        throw RpcFailure(
          RpcResult(
            success: false,
            errorCode: 'RPC_NOT_APPLIED',
            errorMessage: 'Database function "$functionName" is missing. Apply migration: $_migrationHint',
          ),
        );
      }
      if (error.code == '42501' || message.contains('permission denied')) {
        throw RpcFailure(
          RpcResult(
            success: false,
            errorCode: 'RPC_NOT_CONFIGURED',
            errorMessage: 'Database permissions are incomplete. Apply migration: $_migrationHint',
          ),
        );
      }

      final code = _extractShiftErrorCode(message);
      throw RpcFailure(RpcResult(success: false, errorCode: code, errorMessage: message));
    }
  }

  static String _extractShiftErrorCode(String message) {
    const knownCodes = <String>[
      'permission_denied',
      'shift_not_found',
      'shift_cancelled',
      'shift_read_only_past_date',
      'shift_invalid_time_range',
      'shift_overlap',
      'staff_not_eligible',
      'staff_already_assigned',
      'stale_shift',
      'notes_too_long',
      'invalid_shift_date',
      'invalid_date_range',
    ];

    for (final code in knownCodes) {
      if (message.startsWith(code) || message.contains(code)) {
        return code;
      }
    }
    return 'POSTGREST_ERROR';
  }

  static String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static RpcFailure _clientInputFailure(String message) {
    return RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: message));
  }
}

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  return ShiftRepository(ref.watch(supabaseClientProvider));
});
