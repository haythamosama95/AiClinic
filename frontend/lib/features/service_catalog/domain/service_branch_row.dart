import 'package:flutter/foundation.dart';

/// Per-branch configuration row returned by `get_service` (Service Catalog 015).
@immutable
class ServiceBranchRow {
  const ServiceBranchRow({
    required this.serviceBranchId,
    required this.branchId,
    required this.status,
    this.priceOverride,
    this.promotionPrice,
    this.promotionStartDate,
    this.promotionEndDate,
    this.updatedAt,
  });

  final String serviceBranchId;
  final String branchId;
  final String status;
  final String? priceOverride;
  final String? promotionPrice;
  final String? promotionStartDate;
  final String? promotionEndDate;
  final DateTime? updatedAt;

  static ServiceBranchRow? fromRow(Map<String, dynamic> row) {
    final serviceBranchId = row['service_branch_id']?.toString();
    final branchId = row['branch_id']?.toString();
    final status = row['status']?.toString();
    if (serviceBranchId == null ||
        serviceBranchId.isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
        status == null ||
        status.isEmpty) {
      return null;
    }

    final updatedAtRaw = row['updated_at']?.toString();
    final updatedAt = updatedAtRaw == null ? null : DateTime.tryParse(updatedAtRaw);

    String? optionalWire(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return ServiceBranchRow(
      serviceBranchId: serviceBranchId,
      branchId: branchId,
      status: status,
      priceOverride: optionalWire(row['price_override']),
      promotionPrice: optionalWire(row['promotion_price']),
      promotionStartDate: optionalWire(row['promotion_start_date']),
      promotionEndDate: optionalWire(row['promotion_end_date']),
      updatedAt: updatedAt,
    );
  }
}
