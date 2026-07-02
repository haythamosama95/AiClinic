import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Organization catalog row (medication, investigation, or predefined vital sign).
@immutable
class CatalogItem {
  const CatalogItem({required this.id, required this.name, this.defaultUnit});

  final String id;
  final String name;
  final String? defaultUnit;

  static CatalogItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();

    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }

    return CatalogItem(id: id, name: name, defaultUnit: optionalVisitString(row['default_unit']));
  }
}

/// Result of `create_catalog_*` / `create_predefined_vital_sign`.
@immutable
class CatalogCreateResult {
  const CatalogCreateResult({required this.id, required this.name, this.defaultUnit, required this.created});

  final String id;
  final String name;
  final String? defaultUnit;
  final bool created;

  static CatalogCreateResult? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final id = data['id']?.toString();
    final name = data['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }
    return CatalogCreateResult(
      id: id,
      name: name,
      defaultUnit: optionalVisitString(data['default_unit']),
      created: data['created'] == true,
    );
  }
}

/// Result of dev-only `dev_seed_medications_catalog` / `dev_seed_investigations_catalog` batch import.
@immutable
class DevCatalogSeedResult {
  const DevCatalogSeedResult({required this.inserted, required this.requested});

  final int inserted;
  final int requested;
}
