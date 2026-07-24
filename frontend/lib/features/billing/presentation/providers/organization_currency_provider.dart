import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';

/// Organization ISO 4217 currency for billing display when invoice currency is unavailable.
final organizationCurrencyProvider = Provider.autoDispose<String>((ref) {
  final code = ref
      .watch(clinicSetupOrganizationProvider)
      .asData
      ?.value
      ?.currencyCode
      ?.trim();
  if (code != null && code.isNotEmpty) {
    return code.toUpperCase();
  }
  return 'USD';
});
