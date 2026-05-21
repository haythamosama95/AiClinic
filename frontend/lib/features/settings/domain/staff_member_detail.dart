import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter/foundation.dart';

/// Staff member loaded for settings edit form (V1-2).
@immutable
class StaffMemberDetail {
  const StaffMemberDetail({
    required this.id,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.branchIds,
    this.phone,
    this.primaryBranchId,
  });

  final String id;
  final String fullName;
  final StaffRole role;
  final bool isActive;
  final String? phone;
  final List<String> branchIds;
  final String? primaryBranchId;

  static StaffMemberDetail? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final fullName = row['full_name']?.toString().trim();
    final role = StaffRole.tryParse(row['role']?.toString());
    if (id == null || id.isEmpty || fullName == null || fullName.isEmpty || role == null) {
      return null;
    }

    String? optionalString(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final assignments = _parseAssignments(row['staff_branch_assignments']);
    final branchIds = assignments.map((a) => a.branchId).toList(growable: false);
    final primary = assignments.where((a) => a.isPrimary).map((a) => a.branchId).firstOrNull;

    return StaffMemberDetail(
      id: id,
      fullName: fullName,
      role: role,
      isActive: _parseIsActive(row['is_active']),
      phone: optionalString(row['phone']),
      branchIds: branchIds,
      primaryBranchId: primary ?? (branchIds.length == 1 ? branchIds.first : null),
    );
  }

  static bool _parseIsActive(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == 't' || text == '1';
  }

  static List<_AssignmentRow> _parseAssignments(Object? value) {
    if (value is! List) {
      return const [];
    }
    final rows = <_AssignmentRow>[];
    for (final entry in value) {
      if (entry is! Map) {
        continue;
      }
      final branchId = entry['branch_id']?.toString();
      if (branchId == null || branchId.isEmpty) {
        continue;
      }
      final isDeleted = entry['is_deleted'];
      if (isDeleted == true || isDeleted?.toString().toLowerCase() == 'true') {
        continue;
      }
      rows.add(_AssignmentRow(branchId: branchId, isPrimary: _parseIsActive(entry['is_primary'])));
    }
    return rows;
  }
}

class _AssignmentRow {
  const _AssignmentRow({required this.branchId, required this.isPrimary});

  final String branchId;
  final bool isPrimary;
}
