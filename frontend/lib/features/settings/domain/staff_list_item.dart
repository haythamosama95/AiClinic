import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter/foundation.dart';

/// Branch label for a staff list row, with optional primary flag.
@immutable
class StaffBranchLabel {
  const StaffBranchLabel({this.id, required this.name, this.isPrimary = false});

  final String? id;
  final String name;
  final bool isPrimary;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is StaffBranchLabel &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            isPrimary == other.isPrimary;
  }

  @override
  int get hashCode => Object.hash(id, name, isPrimary);
}

/// Staff row for administration list (V1-2).
@immutable
class StaffListItem {
  const StaffListItem({
    required this.id,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.phone,
    this.username,
    this.branches = const [],
  });

  final String id;
  final String fullName;
  final StaffRole role;
  final bool isActive;
  final String? phone;
  final String? username;
  final List<StaffBranchLabel> branches;

  static int compareByFullName(StaffListItem a, StaffListItem b) {
    return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
  }

  static StaffListItem? fromRow(Map<String, dynamic> row) {
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

    return StaffListItem(
      id: id,
      fullName: fullName,
      role: role,
      isActive: _parseIsActive(row['is_active']),
      phone: optionalString(row['phone']),
      username: optionalString(row['username']),
      branches: const [],
    );
  }

  static bool _parseIsActive(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == 't' || text == '1';
  }

  StaffListItem copyWith({
    String? id,
    String? fullName,
    StaffRole? role,
    bool? isActive,
    Object? phone = copyWithSentinel,
    Object? username = copyWithSentinel,
    List<StaffBranchLabel>? branches,
  }) {
    return StaffListItem(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      phone: identical(phone, copyWithSentinel) ? this.phone : phone as String?,
      username: identical(username, copyWithSentinel) ? this.username : username as String?,
      branches: branches ?? this.branches,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is StaffListItem &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            fullName == other.fullName &&
            role == other.role &&
            isActive == other.isActive &&
            phone == other.phone &&
            username == other.username &&
            listEquals(branches, other.branches);
  }

  @override
  int get hashCode => Object.hash(id, fullName, role, isActive, phone, username, Object.hashAll(branches));
}
