import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';

/// Why a service cannot be selected at a branch (Service Catalog 015).
enum EligibilityReason {
  globalInactive('GLOBAL_INACTIVE'),
  notAssigned('NOT_ASSIGNED'),
  branchInactive('BRANCH_INACTIVE');

  const EligibilityReason(this.wireValue);

  final String wireValue;

  static EligibilityReason? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    for (final reason in EligibilityReason.values) {
      if (reason.wireValue == raw) {
        return reason;
      }
    }
    return null;
  }
}

/// Pure eligibility descriptor from `resolve_effective_service_price`.
class ServiceEligibility {
  const ServiceEligibility({required this.eligible, this.price, this.reason});

  final bool eligible;
  final EffectivePrice? price;
  final EligibilityReason? reason;

  static ServiceEligibility fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return const ServiceEligibility(eligible: false);
    }

    final eligible = data['eligible'] == true;
    if (!eligible) {
      return ServiceEligibility(eligible: false, reason: EligibilityReason.tryParse(data['reason']?.toString()));
    }

    return ServiceEligibility(eligible: true, price: EffectivePrice.fromRpcData(data));
  }
}
