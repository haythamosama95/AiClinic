import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter/foundation.dart';

/// Result payload from [modify_shift_assignments] RPC (V1-7 US3).
@immutable
class ShiftAssignmentResult {
  const ShiftAssignmentResult({
    required this.shiftId,
    required this.status,
    required this.assigneeCount,
    required this.updatedAt,
  });

  final String shiftId;
  final ShiftStatus status;
  final int assigneeCount;
  final DateTime updatedAt;

  static ShiftAssignmentResult? fromRpcData(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final data = Map<String, dynamic>.from(raw);
    final shiftId = data['shift_id']?.toString();
    final status = ShiftStatus.tryParse(data['status']?.toString()) ?? ShiftStatus.unknown;
    final assigneeCount = data['assignee_count'];
    final updatedAtRaw = data['updated_at']?.toString();

    if (shiftId == null || shiftId.isEmpty || assigneeCount is! num) {
      return null;
    }

    final updatedAt = updatedAtRaw == null || updatedAtRaw.isEmpty ? null : DateTime.tryParse(updatedAtRaw)?.toUtc();
    if (updatedAt == null) {
      return null;
    }

    return ShiftAssignmentResult(
      shiftId: shiftId,
      status: status,
      assigneeCount: assigneeCount.toInt(),
      updatedAt: updatedAt,
    );
  }
}
