import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';

/// Organization-scoped catalog service (Service Catalog 015).
class Service {
  const Service({
    required this.id,
    required this.name,
    required this.defaultPrice,
    required this.globalStatus,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final Money defaultPrice;
  final GlobalStatus globalStatus;
  final DateTime createdAt;
  final DateTime? updatedAt;

  static Service? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString();
    final defaultPrice = Money.tryParse(row['default_price']?.toString());
    final globalStatus = GlobalStatus.tryParse(row['global_status']?.toString());
    final createdAtRaw = row['created_at']?.toString();
    if (id == null || id.isEmpty || name == null || name.isEmpty || defaultPrice == null || globalStatus == null) {
      return null;
    }
    if (createdAtRaw == null) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      return null;
    }

    final updatedAtRaw = row['updated_at']?.toString();
    final updatedAt = updatedAtRaw == null ? null : DateTime.tryParse(updatedAtRaw);

    return Service(
      id: id,
      name: name,
      defaultPrice: defaultPrice,
      globalStatus: globalStatus,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
