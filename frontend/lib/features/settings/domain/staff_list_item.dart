import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter/foundation.dart';

/// Staff row for administration list (V1-2).
@immutable
class StaffListItem {
  const StaffListItem({
    required this.id,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.phone,
    this.branchNames = const [],
  });

  final String id;
  final String fullName;
  final StaffRole role;
  final bool isActive;
  final String? phone;
  final List<String> branchNames;

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
      branchNames: const [],
    );
  }

  static bool _parseIsActive(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == 't' || text == '1';
  }

  /// Comma-separated branch labels for list subtitle.
  String get branchNamesLabel {
    if (branchNames.isEmpty) {
      return 'No branches assigned';
    }
    return branchNames.join(', ');
  }

  StaffListItem copyWith({
    String? id,
    String? fullName,
    StaffRole? role,
    bool? isActive,
    String? phone,
    List<String>? branchNames,
  }) {
    return StaffListItem(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      phone: phone ?? this.phone,
      branchNames: branchNames ?? this.branchNames,
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
            listEquals(branchNames, other.branchNames);
  }

  @override
  int get hashCode => Object.hash(id, fullName, role, isActive, phone, Object.hashAll(branchNames));
}
