import 'package:flutter/foundation.dart';

/// Organization-scoped insurance provider catalog entry (V1-6).
@immutable
class InsuranceProvider {
  const InsuranceProvider({required this.id, required this.name, required this.isActive, this.contactInfo});

  final String id;
  final String name;
  final String? contactInfo;
  final bool isActive;

  static InsuranceProvider? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }

    return InsuranceProvider(
      id: id,
      name: name,
      contactInfo: row['contact_info']?.toString(),
      isActive: row['is_active'] == true || row['is_active']?.toString() == 'true',
    );
  }
}
