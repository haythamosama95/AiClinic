import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';

/// Branch-specific summary attached to a catalog list row when filtering by branch.
@immutable
class ServiceBranchSummary {
  const ServiceBranchSummary({required this.status, required this.effectivePrice, required this.onPromotion});

  final String status;
  final Money effectivePrice;
  final bool onPromotion;

  static ServiceBranchSummary? fromRow(Map<String, dynamic>? row) {
    if (row == null) {
      return null;
    }
    final status = row['status']?.toString();
    final effectivePrice = Money.tryParse(row['effective_price']?.toString());
    if (status == null || status.isEmpty || effectivePrice == null) {
      return null;
    }
    return ServiceBranchSummary(
      status: status,
      effectivePrice: effectivePrice,
      onPromotion: row['on_promotion'] == true,
    );
  }
}

/// Paginated catalog row for the management list (Service Catalog 015 US6).
@immutable
class ServiceListItem {
  const ServiceListItem({
    required this.serviceId,
    required this.name,
    required this.defaultPrice,
    required this.globalStatus,
    required this.assignedBranchCount,
    required this.updatedAt,
    this.branchSummary,
  });

  final String serviceId;
  final String name;
  final Money defaultPrice;
  final GlobalStatus globalStatus;
  final int assignedBranchCount;
  final DateTime updatedAt;
  final ServiceBranchSummary? branchSummary;

  static ServiceListItem? fromRow(Map<String, dynamic> row) {
    final serviceId = row['service_id']?.toString();
    final name = row['name']?.toString();
    final defaultPrice = Money.tryParse(row['default_price']?.toString());
    final globalStatus = GlobalStatus.tryParse(row['global_status']?.toString());
    final assignedBranchCount = row['assigned_branch_count'];
    final updatedAtRaw = row['updated_at']?.toString();
    if (serviceId == null ||
        serviceId.isEmpty ||
        name == null ||
        name.isEmpty ||
        defaultPrice == null ||
        globalStatus == null ||
        assignedBranchCount is! num ||
        updatedAtRaw == null) {
      return null;
    }
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (updatedAt == null) {
      return null;
    }

    final summaryRaw = row['branch_summary'];
    ServiceBranchSummary? branchSummary;
    if (summaryRaw is Map<String, dynamic>) {
      branchSummary = ServiceBranchSummary.fromRow(summaryRaw);
    } else if (summaryRaw is Map) {
      branchSummary = ServiceBranchSummary.fromRow(Map<String, dynamic>.from(summaryRaw));
    }

    return ServiceListItem(
      serviceId: serviceId,
      name: name,
      defaultPrice: defaultPrice,
      globalStatus: globalStatus,
      assignedBranchCount: assignedBranchCount.toInt(),
      updatedAt: updatedAt,
      branchSummary: branchSummary,
    );
  }
}
