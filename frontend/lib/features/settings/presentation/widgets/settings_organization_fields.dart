import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';

/// Organization profile fields for settings view and edit modes.
class SettingsOrganizationFields extends StatelessWidget {
  const SettingsOrganizationFields({
    required this.isEditing,
    required this.nameController,
    required this.logoUrlController,
    required this.currency,
    required this.timezone,
    required this.onCurrencyChanged,
    required this.onTimezoneChanged,
    required this.profile,
    required this.disabled,
    this.fieldErrors = const {},
    super.key,
  });

  final bool isEditing;
  final TextEditingController nameController;
  final TextEditingController logoUrlController;
  final String? currency;
  final String? timezone;
  final ValueChanged<String?> onCurrencyChanged;
  final ValueChanged<String?> onTimezoneChanged;
  final OrganizationProfile profile;
  final bool disabled;
  final Map<String, String?> fieldErrors;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) {
      return AppDescriptionList(
        items: [
          AppDescriptionItem(label: 'Organization name', value: Text(profile.name)),
          AppDescriptionItem(label: 'Logo URL', value: Text(profile.logoUrl ?? '—')),
          AppDescriptionItem(label: 'Currency code', value: Text(profile.currencyCode ?? '—')),
          AppDescriptionItem(label: 'Timezone', value: Text(profile.timezone ?? '—')),
          if (profile.subscriptionTier != null)
            AppDescriptionItem(label: 'Subscription tier', value: Text(profile.subscriptionTier!)),
        ],
      );
    }

    final currencyOptions = [
      for (final code in BootstrapCurrencyOptions.codes)
        AppSelectOption<String>(value: code, label: code),
    ];
    final timezoneOptions = [
      for (final zone in BootstrapTimezoneOptions.zones)
        AppSelectOption<String>(value: zone, label: zone),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFormField(
          label: 'Organization name',
          requiredMark: true,
          error: fieldErrors['name'],
          child: AppTextField(
            controller: nameController,
            hintText: 'Enter your clinic name',
            disabled: disabled,
            invalid: fieldErrors['name'] != null,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Logo URL',
          hint: 'HTTPS link to your clinic logo.',
          error: fieldErrors['logoUrl'],
          child: AppTextField(
            controller: logoUrlController,
            hintText: 'https://example.com/logo.png',
            disabled: disabled,
            keyboardType: TextInputType.url,
            invalid: fieldErrors['logoUrl'] != null,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Currency code',
          requiredMark: true,
          hint: 'ISO 4217 code for billing and receipts (e.g. EGP, USD).',
          error: fieldErrors['currency'],
          child: AppSelect<String>(
            options: currencyOptions,
            value: currency,
            placeholder: 'Type to search (e.g. EGP)',
            disabled: disabled,
            invalid: fieldErrors['currency'] != null,
            onChanged: disabled ? null : onCurrencyChanged,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        AppFormField(
          label: 'Timezone',
          requiredMark: true,
          hint: 'IANA timezone for appointments and daily reports (e.g. Africa/Cairo).',
          error: fieldErrors['timezone'],
          child: AppSelect<String>(
            options: timezoneOptions,
            value: timezone,
            placeholder: 'Type to search (e.g. Africa/Cairo)',
            disabled: disabled,
            invalid: fieldErrors['timezone'] != null,
            onChanged: disabled ? null : onTimezoneChanged,
          ),
        ),
      ],
    );
  }
}
