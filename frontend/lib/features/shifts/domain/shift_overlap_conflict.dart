import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Overlap conflict payload from `shift_overlap` RPC errors (V1-7).
@immutable
class ShiftOverlapConflict {
  const ShiftOverlapConflict({
    required this.staffMemberId,
    required this.displayName,
    required this.conflictingShiftId,
    required this.startTime,
    required this.endTime,
  });

  final String staffMemberId;
  final String displayName;
  final String conflictingShiftId;
  final String startTime;
  final String endTime;

  static ShiftOverlapConflict? fromRow(Map<String, dynamic> row) {
    final staffMemberId = row['staff_member_id']?.toString();
    final displayName = row['display_name']?.toString().trim();
    final conflictingShiftId = row['conflicting_shift_id']?.toString();
    final startTime = row['start_time']?.toString();
    final endTime = row['end_time']?.toString();

    if (staffMemberId == null ||
        staffMemberId.isEmpty ||
        displayName == null ||
        displayName.isEmpty ||
        conflictingShiftId == null ||
        conflictingShiftId.isEmpty ||
        startTime == null ||
        startTime.isEmpty ||
        endTime == null ||
        endTime.isEmpty) {
      return null;
    }

    return ShiftOverlapConflict(
      staffMemberId: staffMemberId,
      displayName: displayName,
      conflictingShiftId: conflictingShiftId,
      startTime: startTime,
      endTime: endTime,
    );
  }

  static List<ShiftOverlapConflict> parseFromRpcMessage(String message) {
    const prefix = 'shift_overlap:';
    final start = message.indexOf(prefix);
    if (start < 0) {
      return const [];
    }

    final jsonPart = message.substring(start + prefix.length).trim();
    try {
      final decoded = jsonDecode(jsonPart);
      return parseList(decoded);
    } catch (_) {
      return const [];
    }
  }

  static List<ShiftOverlapConflict> parseList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }

    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          ShiftOverlapConflict.fromRow(item)
        else if (item is Map)
          ShiftOverlapConflict.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<ShiftOverlapConflict>().toList(growable: false);
  }
}
