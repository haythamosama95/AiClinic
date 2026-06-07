import 'package:ai_clinic/features/shifts/domain/shift_assignment.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter/foundation.dart';

/// Branch summary bundled with shift detail (V1-7).
@immutable
class ShiftBranchSummary {
  const ShiftBranchSummary({required this.id, required this.name, this.code});

  final String id;
  final String name;
  final String? code;

  static ShiftBranchSummary? fromRow(Map<String, dynamic>? row) {
    if (row == null) {
      return null;
    }
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }
    final codeRaw = row['code']?.toString().trim();
    final code = codeRaw == null || codeRaw.isEmpty ? null : codeRaw;
    return ShiftBranchSummary(id: id, name: name, code: code);
  }
}

/// Full shift detail with assignments and read-only flags (V1-7).
@immutable
class ShiftDetail {
  const ShiftDetail({
    required this.id,
    required this.branchId,
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.isUnassigned,
    required this.isPast,
    required this.isReadOnly,
    required this.assignments,
    required this.branch,
    this.notes,
    this.updatedAt,
  });

  final String id;
  final String branchId;
  final DateTime shiftDate;
  final String startTime;
  final String endTime;
  final String? notes;
  final ShiftStatus status;
  final bool isUnassigned;
  final bool isPast;
  final bool isReadOnly;
  final DateTime? updatedAt;
  final List<ShiftAssignment> assignments;
  final ShiftBranchSummary branch;

  static String? _notesPreview(String? notes) {
    final trimmed = notes?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.length <= 80 ? trimmed : trimmed.substring(0, 80);
  }

  ShiftListItem toListItem() {
    return ShiftListItem(
      id: id,
      branchId: branchId,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      status: status,
      isUnassigned: isUnassigned,
      assigneeNames: [for (final a in assignments) a.displayName],
      assigneeCount: assignments.length,
      notesPreview: _notesPreview(notes),
    );
  }

  static ShiftDetail? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final shiftRaw = data['shift'];
    if (shiftRaw is! Map) {
      return null;
    }
    final shift = Map<String, dynamic>.from(shiftRaw);

    final id = shift['id']?.toString();
    final branchId = shift['branch_id']?.toString();
    final shiftDate = ShiftListItem.fromRow({
      ...shift,
      'assignee_names': const <String>[],
      'assignee_count': 0,
    })?.shiftDate;
    final startTime = shift['start_time']?.toString().trim();
    final endTime = shift['end_time']?.toString().trim();
    final notesRaw = shift['notes']?.toString().trim();
    final notes = notesRaw == null || notesRaw.isEmpty ? null : notesRaw;
    final status = ShiftStatus.tryParse(shift['status']?.toString()) ?? ShiftStatus.unknown;
    final isUnassigned = shift['is_unassigned'] == true;
    final isPast = shift['is_past'] == true;
    final isReadOnly = shift['is_read_only'] == true;
    final updatedAtRaw = shift['updated_at']?.toString();
    final updatedAt = updatedAtRaw == null || updatedAtRaw.isEmpty ? null : DateTime.tryParse(updatedAtRaw)?.toUtc();

    final assignmentsRaw = data['assignments'];
    final assignments = [
      if (assignmentsRaw is List)
        for (final item in assignmentsRaw)
          if (item is Map<String, dynamic>)
            ShiftAssignment.fromRow(item)
          else if (item is Map)
            ShiftAssignment.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<ShiftAssignment>().toList(growable: false);

    final branch = ShiftBranchSummary.fromRow(
      data['branch'] is Map ? Map<String, dynamic>.from(data['branch'] as Map) : null,
    );

    if (id == null ||
        id.isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
        shiftDate == null ||
        startTime == null ||
        startTime.isEmpty ||
        endTime == null ||
        endTime.isEmpty ||
        branch == null) {
      return null;
    }

    return ShiftDetail(
      id: id,
      branchId: branchId,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      notes: notes,
      status: status,
      isUnassigned: isUnassigned,
      isPast: isPast,
      isReadOnly: isReadOnly,
      updatedAt: updatedAt,
      assignments: assignments,
      branch: branch,
    );
  }
}
