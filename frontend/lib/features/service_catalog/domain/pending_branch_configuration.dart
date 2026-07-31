import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/service_catalog/domain/service_promotion.dart';

/// Branch settings collected during service create before the service exists (015 US3+US4).
@immutable
class PendingBranchConfiguration {
  const PendingBranchConfiguration({
    required this.branchId,
    this.branchName,
    this.active = true,
    this.priceOverride,
    this.promotion,
  });

  final String branchId;
  final String? branchName;
  final bool active;
  final String? priceOverride;
  final ServicePromotion? promotion;

  bool get hasBranchSettingsChange => !active || (priceOverride != null && priceOverride!.isNotEmpty);

  bool get hasPromotion => promotion != null;

  PendingBranchConfiguration copyWith({
    bool? active,
    String? priceOverride,
    bool clearPriceOverride = false,
    ServicePromotion? promotion,
    bool clearPromotion = false,
    String? branchName,
  }) {
    return PendingBranchConfiguration(
      branchId: branchId,
      branchName: branchName ?? this.branchName,
      active: active ?? this.active,
      priceOverride: clearPriceOverride ? null : (priceOverride ?? this.priceOverride),
      promotion: clearPromotion ? null : (promotion ?? this.promotion),
    );
  }
}
