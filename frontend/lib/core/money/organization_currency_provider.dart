import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/money/money_formatter.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';

/// Organization currency code for price display, falling back when unset.
final organizationCurrencyProvider = Provider<String>((ref) {
  final currencyCode = ref.watch(clinicSetupOrganizationProvider).asData?.value?.currencyCode?.trim();
  if (currencyCode != null && currencyCode.isNotEmpty) {
    return currencyCode;
  }
  return MoneyFormatter.fallbackCurrencyCode;
});
