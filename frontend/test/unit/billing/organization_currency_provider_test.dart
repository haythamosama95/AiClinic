import 'dart:async';

import 'package:ai_clinic/features/billing/presentation/providers/organization_currency_provider.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/settings_test_support.dart';

void main() {
  group('organizationCurrencyProvider', () {
    test('uppercases a configured currency code', () async {
      final container = ProviderContainer(
        overrides: [
          clinicSetupOrganizationProvider.overrideWith(
            (ref) => Future.value(sampleOrganizationProfile(currencyCode: 'egp')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(clinicSetupOrganizationProvider.future);

      expect(container.read(organizationCurrencyProvider), 'EGP');
    });

    test('trims whitespace before uppercasing', () async {
      final container = ProviderContainer(
        overrides: [
          clinicSetupOrganizationProvider.overrideWith(
            (ref) => Future.value(sampleOrganizationProfile(currencyCode: '  usd  ')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(clinicSetupOrganizationProvider.future);

      expect(container.read(organizationCurrencyProvider), 'USD');
    });

    test('defaults to USD when currency code is null', () async {
      final container = ProviderContainer(
        overrides: [
          clinicSetupOrganizationProvider.overrideWith(
            (ref) => Future.value(sampleOrganizationProfile(currencyCode: null)),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(clinicSetupOrganizationProvider.future);

      expect(container.read(organizationCurrencyProvider), 'USD');
    });

    test('defaults to USD when currency code is empty', () async {
      final container = ProviderContainer(
        overrides: [
          clinicSetupOrganizationProvider.overrideWith(
            (ref) => Future.value(sampleOrganizationProfile(currencyCode: '')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(clinicSetupOrganizationProvider.future);

      expect(container.read(organizationCurrencyProvider), 'USD');
    });

    test('defaults to USD when currency code is whitespace', () async {
      final container = ProviderContainer(
        overrides: [
          clinicSetupOrganizationProvider.overrideWith(
            (ref) => Future.value(sampleOrganizationProfile(currencyCode: '   ')),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(clinicSetupOrganizationProvider.future);

      expect(container.read(organizationCurrencyProvider), 'USD');
    });

    test('defaults to USD while organization profile is still loading', () {
      final container = ProviderContainer(
        overrides: [
          clinicSetupOrganizationProvider.overrideWith(
            (ref) => Completer<OrganizationProfile?>().future,
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(organizationCurrencyProvider), 'USD');
    });
  });
}
