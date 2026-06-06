import 'package:flutter/foundation.dart';

/// Staff assignment on a shift (V1-7).
@immutable
class ShiftAssignment {
  const ShiftAssignment({required this.id, required this.staffMemberId, required this.displayName});

  final String id;
  final String staffMemberId;
  final String displayName;

  static ShiftAssignment? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final staffMemberId = row['staff_member_id']?.toString();
    final displayName = row['display_name']?.toString().trim();

    if (id == null ||
        id.isEmpty ||
        staffMemberId == null ||
        staffMemberId.isEmpty ||
        displayName == null ||
        displayName.isEmpty) {
      return null;
    }

    return ShiftAssignment(id: id, staffMemberId: staffMemberId, displayName: displayName);
  }
}
