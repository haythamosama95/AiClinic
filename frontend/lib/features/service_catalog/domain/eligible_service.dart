import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';

/// Eligible catalog row returned by `search_eligible_services` (Service Catalog 015 US2).
class EligibleService {
  const EligibleService({
    required this.serviceId,
    required this.name,
    required this.unitPrice,
    required this.appliedRule,
    required this.onPromotion,
  });

  final String serviceId;
  final String name;
  final Money unitPrice;
  final AppliedPriceRule appliedRule;
  final bool onPromotion;

  static EligibleService? fromRow(Map<String, dynamic> row) {
    final serviceId = row['service_id']?.toString();
    final name = row['name']?.toString();
    final unitPrice = Money.tryParse(row['unit_price']?.toString());
    final appliedRule = AppliedPriceRule.tryParse(row['applied_rule']?.toString());
    if (serviceId == null ||
        serviceId.isEmpty ||
        name == null ||
        name.isEmpty ||
        unitPrice == null ||
        appliedRule == null) {
      return null;
    }

    return EligibleService(
      serviceId: serviceId,
      name: name,
      unitPrice: unitPrice,
      appliedRule: appliedRule,
      onPromotion: row['on_promotion'] == true,
    );
  }
}
