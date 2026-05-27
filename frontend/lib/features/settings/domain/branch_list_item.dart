import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:flutter/foundation.dart';

/// Branch row for administration list and pickers (V1-2).
@immutable
class BranchListItem {
  const BranchListItem({
    required this.id,
    required this.name,
    required this.isActive,
    this.code,
    this.address,
    this.phone,
    this.mapsUrl,
  });

  final String id;
  final String name;
  final bool isActive;
  final String? code;
  final String? address;
  final String? phone;
  final String? mapsUrl;

  static BranchListItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }

    String? optionalString(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return BranchListItem(
      id: id,
      name: name,
      isActive: _parseIsActive(row['is_active']),
      code: optionalString(row['code']),
      address: optionalString(row['address']),
      phone: optionalString(row['phone']),
      mapsUrl: optionalString(row['maps_url']),
    );
  }

  static bool _parseIsActive(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == 't' || text == '1';
  }

  /// Branch code normalized for uniqueness checks (lowercase, trimmed).
  static String? normalizeCode(String? input) {
    final trimmed = input?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.toLowerCase();
  }

  BranchListItem copyWith({
    String? id,
    String? name,
    bool? isActive,
    Object? code = copyWithSentinel,
    Object? address = copyWithSentinel,
    Object? phone = copyWithSentinel,
    Object? mapsUrl = copyWithSentinel,
  }) {
    return BranchListItem(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      code: identical(code, copyWithSentinel) ? this.code : code as String?,
      address: identical(address, copyWithSentinel) ? this.address : address as String?,
      phone: identical(phone, copyWithSentinel) ? this.phone : phone as String?,
      mapsUrl: identical(mapsUrl, copyWithSentinel) ? this.mapsUrl : mapsUrl as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BranchListItem &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            isActive == other.isActive &&
            code == other.code &&
            address == other.address &&
            phone == other.phone &&
            mapsUrl == other.mapsUrl;
  }

  @override
  int get hashCode => Object.hash(id, name, isActive, code, address, phone, mapsUrl);
}
