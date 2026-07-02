import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_branch_row.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_promotion.dart';

/// Per-branch activation, override, and promotion for the editor (Service Catalog 015 US3).
@immutable
class ServiceBranchConfig {
  const ServiceBranchConfig({
    required this.serviceBranchId,
    required this.branchId,
    required this.status,
    this.priceOverride,
    this.promotion,
    this.updatedAt,
    this.branchName,
  });

  final String serviceBranchId;
  final String branchId;
  final String status;
  final Money? priceOverride;
  final ServicePromotion? promotion;
  final DateTime? updatedAt;
  final String? branchName;

  bool get isActive => status == 'active';

  ServiceBranchConfig copyWith({
    String? status,
    Money? priceOverride,
    bool clearPriceOverride = false,
    ServicePromotion? promotion,
    bool clearPromotion = false,
    DateTime? updatedAt,
    String? branchName,
  }) {
    return ServiceBranchConfig(
      serviceBranchId: serviceBranchId,
      branchId: branchId,
      status: status ?? this.status,
      priceOverride: clearPriceOverride ? null : (priceOverride ?? this.priceOverride),
      promotion: clearPromotion ? null : (promotion ?? this.promotion),
      updatedAt: updatedAt ?? this.updatedAt,
      branchName: branchName ?? this.branchName,
    );
  }

  static ServiceBranchConfig fromRow(ServiceBranchRow row, {String? branchName}) {
    return ServiceBranchConfig(
      serviceBranchId: row.serviceBranchId,
      branchId: row.branchId,
      status: row.status,
      priceOverride: row.priceOverride == null ? null : Money.tryParse(row.priceOverride!),
      promotion: ServicePromotion.tryParse(
        price: row.promotionPrice,
        startDate: row.promotionStartDate,
        endDate: row.promotionEndDate,
      ),
      updatedAt: row.updatedAt,
      branchName: branchName,
    );
  }
}
