import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter/foundation.dart';

/// Shift row for calendar and list views (V1-7).
@immutable
class ShiftListItem {
  const ShiftListItem({
    required this.id,
    required this.branchId,
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.isUnassigned,
    required this.assigneeNames,
    required this.assigneeCount,
    this.notesPreview,
  });

  final String id;
  final String branchId;
  final DateTime shiftDate;
  final String startTime;
  final String endTime;
  final ShiftStatus status;
  final bool isUnassigned;
  final List<String> assigneeNames;
  final int assigneeCount;
  final String? notesPreview;

  String get assigneeSummary {
    if (assigneeNames.isEmpty) {
      return 'Unassigned';
    }
    if (assigneeNames.length <= 2) {
      return assigneeNames.join(', ');
    }
    return '${assigneeNames.take(2).join(', ')} +${assigneeNames.length - 2}';
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static List<String> _parseAssigneeNames(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final name in raw)
        if (name != null) name.toString().trim(),
    ].where((name) => name.isNotEmpty).toList(growable: false);
  }

  static ShiftListItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final branchId = row['branch_id']?.toString();
    final shiftDate = _parseDate(row['shift_date']);
    final startTime = row['start_time']?.toString().trim();
    final endTime = row['end_time']?.toString().trim();
    final status = ShiftStatus.tryParse(row['status']?.toString()) ?? ShiftStatus.unknown;
    final isUnassigned = row['is_unassigned'] == true;
    final assigneeNames = _parseAssigneeNames(row['assignee_names']);
    final assigneeCount = int.tryParse(row['assignee_count']?.toString() ?? '') ?? assigneeNames.length;
    final notesPreviewRaw = row['notes_preview']?.toString().trim();
    final notesPreview = notesPreviewRaw == null || notesPreviewRaw.isEmpty ? null : notesPreviewRaw;

    if (id == null ||
        id.isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
        shiftDate == null ||
        startTime == null ||
        startTime.isEmpty ||
        endTime == null ||
        endTime.isEmpty) {
      return null;
    }

    return ShiftListItem(
      id: id,
      branchId: branchId,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      status: status,
      isUnassigned: isUnassigned,
      assigneeNames: assigneeNames,
      assigneeCount: assigneeCount,
      notesPreview: notesPreview,
    );
  }
}
